import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../models/widget_member_dto.dart';
import '../utils/time_utils.dart';
import 'api_service.dart';

/// iOS: set the same identifier on the main app + widget extension targets
/// (Signing & Capabilities → App Groups). Android ignores this call.
const String kZelliaIosAppGroupId = 'group.one.dothings.zellia';

/// Must match native widget provider / kind names after you add targets.
const String kAndroidWidgetProviderName = 'ZelliaMemberWidgetProvider';
const String kIosWidgetKindName = 'ZelliaMemberWidget';

/// Fully-qualified Android [AppWidgetProvider] for [HomeWidget.updateWidget] / pin.
const String kQualifiedAndroidWidgetProvider =
    'one.dothings.zellia.ZelliaMemberWidgetProvider';

const String _kCachedMembersKey = 'cached_widget_members';
const String kPendingPinMemberIdKey = 'pending_pin_member_id';

String memberDataKey(String memberId) => 'member_data_$memberId';

/// Multi-member desktop widgets: per-member JSON + index for background refresh.
class HomeWidgetService {
  HomeWidgetService._();

  static final HomeWidgetService instance = HomeWidgetService._();

  static bool _didInit = false;

  /// Call once after `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<void> initialize() async {
    if (_didInit) return;
    _didInit = true;
    try {
      await HomeWidget.setAppGroupId(kZelliaIosAppGroupId);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[HomeWidget] setAppGroupId failed (ok on non‑iOS): $e');
        debugPrint('$st');
      }
    }
  }

  /// Wire silent sync into [ApiService] without circular imports.
  static void registerApiHooks() {
    ApiService.onPostApprovedEldersLoad = (api, elders) {
      scheduleMicrotask(() => instance._afterApprovedEldersLoaded(api, elders));
    };
    ApiService.onPostTargetUserClinicalRefresh = (api, targetUserId) {
      scheduleMicrotask(() => instance._syncMemberIfCached(api, targetUserId));
    };
  }

  /// Foreground FCM: refresh every pinned member so vitals/meds stay aligned with push events.
  static Future<void> refreshAllCachedMembers(ApiService api) async {
    await instance._refreshAllCached(api);
  }

  Future<void> _updateAllWidgets() async {
    try {
      await HomeWidget.updateWidget(
        name: kAndroidWidgetProviderName,
        androidName: kAndroidWidgetProviderName,
        qualifiedAndroidName: kQualifiedAndroidWidgetProvider,
        iOSName: kIosWidgetKindName,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[HomeWidget] updateWidget failed: $e');
        debugPrint('$st');
      }
    }
  }

  /// Writes vitals JSON under `member_data_<memberId>` and refreshes widget timelines.
  ///
  /// [isNormal] maps to JSON field `isBpNormal` for the native widget parser.
  Future<void> syncMemberData({
    required String memberId,
    required String nickname,
    required String latestBp,
    required bool isNormal,
    bool medTakenToday = false,
    String? updatedAt,
  }) async {
    try {
      await HomeWidgetService.initialize();
      final mid = memberId.trim();
      if (mid.isEmpty) return;
      final at = updatedAt ?? _formatUpdatedAt(DateTime.now());
      final payload = jsonEncode(<String, dynamic>{
        'userId': mid,
        'nickname': nickname,
        'latestBp': latestBp,
        'isBpNormal': isNormal,
        'medTakenToday': medTakenToday,
        'updatedAt': at,
      });
      await HomeWidget.saveWidgetData<String>(memberDataKey(mid), payload);
      // Drop legacy key so Android never reads stale `widget_data_*`.
      await HomeWidget.saveWidgetData<String>('widget_data_$mid', null);
      final ids = await _readCachedMemberIds();
      ids.add(mid);
      await HomeWidget.saveWidgetData<String>(
        _kCachedMembersKey,
        ids.join(','),
      );
      await _updateAllWidgets();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[HomeWidget] syncMemberData failed: $e');
        debugPrint('$st');
      }
    }
  }

  /// Same payload as [syncMemberData], built from [WidgetMemberDto].
  Future<void> syncMemberWidgetData(WidgetMemberDto member) async {
    await syncMemberData(
      memberId: member.userId,
      nickname: member.nickname,
      latestBp: member.latestBp,
      isNormal: member.isBpNormal,
      medTakenToday: member.medTakenToday,
      updatedAt: member.updatedAt,
    );
  }

  /// Android 8+ in-app widget pin. Writes [kPendingPinMemberIdKey] then asks the launcher
  /// to add a new widget instance; the provider binds `appWidgetId` → member on first [onUpdate].
  ///
  /// Returns `false` on unsupported platforms, unsupported OS versions, or channel errors.
  /// With **home_widget 0.9.x**, [HomeWidget.requestPinWidget] returns `void`; a normal
  /// completion (no throw) is treated as **true** (pin flow was handed to the launcher).
  Future<bool> pinWidgetForMember(String memberId) async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      await HomeWidgetService.initialize();
      final mid = memberId.trim();
      if (mid.isEmpty) return false;
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      if (supported != true) return false;
      await HomeWidget.saveWidgetData<String>(kPendingPinMemberIdKey, mid);
      // home_widget 0.9.x: [requestPinWidget] completes with void (no success flag).
      await HomeWidget.requestPinWidget(
        name: kAndroidWidgetProviderName,
        androidName: kAndroidWidgetProviderName,
        qualifiedAndroidName: kQualifiedAndroidWidgetProvider,
      );
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[HomeWidget] pinWidgetForMember failed: $e');
        debugPrint('$st');
      }
      try {
        await HomeWidget.saveWidgetData<String>(kPendingPinMemberIdKey, null);
      } catch (_) {}
      return false;
    }
  }

  /// Unfollow / revoke PRO share: drop widget payload and prune index.
  Future<void> clearMemberWidgetData(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    try {
      await HomeWidgetService.initialize();
      await HomeWidget.saveWidgetData<String>(memberDataKey(uid), null);
      await HomeWidget.saveWidgetData<String>('widget_data_$uid', null);
      final ids = await _readCachedMemberIds();
      ids.remove(uid);
      await HomeWidget.saveWidgetData<String>(
        _kCachedMembersKey,
        ids.isEmpty ? null : ids.join(','),
      );
      await _updateAllWidgets();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[HomeWidget] clearMemberWidgetData failed: $e');
        debugPrint('$st');
      }
    }
  }

  /// Family screen “Add to desktop board”: fetch latest vitals + today meds then persist.
  Future<void> syncMemberFromServerForPin({
    required ApiService api,
    required ApprovedElderDto elder,
  }) async {
    final nickname = (elder.elderAlias ?? '').trim().isNotEmpty
        ? elder.elderAlias!.trim()
        : elder.elderUsername;
    final dto = await _buildDto(
      api: api,
      elderId: elder.elderId,
      nickname: nickname,
    );
    await syncMemberWidgetData(dto);
  }

  Future<Set<String>> _readCachedMemberIds() async {
    try {
      final raw = await HomeWidget.getWidgetData<String>(_kCachedMembersKey);
      if (raw == null || raw.trim().isEmpty) return <String>{};
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _afterApprovedEldersLoaded(
    ApiService api,
    List<ApprovedElderDto> elders,
  ) async {
    final allowed = elders.map((e) => '${e.elderId}').toSet();
    final cached = await _readCachedMemberIds();
    for (final sid in cached) {
      if (!allowed.contains(sid)) {
        await clearMemberWidgetData(sid);
        continue;
      }
      final id = int.tryParse(sid);
      if (id == null) continue;
      ApprovedElderDto? elder;
      for (final e in elders) {
        if (e.elderId == id) {
          elder = e;
          break;
        }
      }
      if (elder == null) continue;
      try {
        final nick = (elder.elderAlias ?? '').trim().isNotEmpty
            ? elder.elderAlias!.trim()
            : elder.elderUsername;
        final dto = await _buildDto(api: api, elderId: id, nickname: nick);
        await syncMemberWidgetData(dto);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[HomeWidget] silent elder $sid sync: $e');
        }
      }
    }
  }

  Future<void> _syncMemberIfCached(ApiService api, int? targetUserId) async {
    if (targetUserId == null) return;
    final sid = '$targetUserId';
    final cached = await _readCachedMemberIds();
    if (!cached.contains(sid)) return;
    try {
      final nick = await _readNicknameFromExistingPayload(sid) ?? '家人';
      final dto = await _buildDto(
        api: api,
        elderId: targetUserId,
        nickname: nick,
      );
      await syncMemberWidgetData(dto);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[HomeWidget] target refresh $sid: $e');
      }
    }
  }

  Future<void> _refreshAllCached(ApiService api) async {
    for (final sid in await _readCachedMemberIds()) {
      final id = int.tryParse(sid);
      if (id == null) continue;
      await _syncMemberIfCached(api, id);
    }
  }

  Future<String?> _readNicknameFromExistingPayload(String userId) async {
    try {
      final rawM = await HomeWidget.getWidgetData<String>(memberDataKey(userId));
      final raw = (rawM != null && rawM.trim().isNotEmpty)
          ? rawM
          : await HomeWidget.getWidgetData<String>('widget_data_$userId');
      if (raw == null || raw.trim().isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final n = (map['nickname'] as String?)?.trim();
      return n != null && n.isNotEmpty ? n : null;
    } catch (_) {
      return null;
    }
  }

  Future<WidgetMemberDto> _buildDto({
    required ApiService api,
    required int elderId,
    required String nickname,
  }) async {
    final bpRows = await api.getBloodPressureHistory(
      page: 1,
      pageSize: 1,
      targetUserId: elderId,
    );
    final latestBp = bpRows.isEmpty
        ? '暂无'
        : '${bpRows.first.systolic}/${bpRows.first.diastolic}';
    final isBpNormal = bpRows.isEmpty
        ? true
        : _isBpNormal(bpRows.first.systolic, bpRows.first.diastolic);
    final medItems = await api.getTodayMedications(targetUserId: elderId);
    final medTakenToday =
        medItems.isEmpty || medItems.every((e) => e.isTaken);
    final updatedAt = _formatUpdatedAt(
      bpRows.isNotEmpty ? bpRows.first.measuredAt : DateTime.now(),
    );
    return WidgetMemberDto(
      userId: '$elderId',
      nickname: nickname,
      latestBp: latestBp,
      isBpNormal: isBpNormal,
      medTakenToday: medTakenToday,
      updatedAt: updatedAt,
    );
  }

  static bool _isBpNormal(int systolic, int diastolic) {
    return systolic < 140 && diastolic < 90;
  }

  static String _formatUpdatedAt(DateTime at) {
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    if (sameDay) {
      return '今天 ${TimeUtils.formatLocalDateTime(at, pattern: 'HH:mm')}';
    }
    return TimeUtils.formatLocalDateTime(at, pattern: 'MM-dd HH:mm');
  }
}

// -----------------------------------------------------------------------------
// Markdown (integration notes for native engineers)
// -----------------------------------------------------------------------------
//
// ### Keys (Flutter ↔ Android / iOS App Group)
// - **Per member JSON**: `member_data_<memberId>` (JSON string).
// - **Pin handshake (Android)**: `pending_pin_member_id` → consumed on first widget [onUpdate].
// - **Per widget instance**: `bound_widget_<appWidgetId>` → member id string.
// - **Background refresh index**: `cached_widget_members` (comma-separated ids).
//
// ### Android
// - Read `SharedPreferences("HomeWidgetPreferences")` (same as Flutter home_widget).
// - Each [appWidgetId] resolves its own [bound_widget_*] then loads `member_data_*`.
//
// ### iOS
// - Same keys in App Group; pin flow is Android-only until WidgetKit pin API is wired.
//
// -----------------------------------------------------------------------------
