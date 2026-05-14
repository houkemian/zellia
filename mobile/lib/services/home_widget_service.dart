import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../models/widget_member_dto.dart';
import 'api_service.dart';

/// iOS: set the same identifier on the main app + widget extension targets
/// (Signing & Capabilities → App Groups). Android ignores this call.
const String kZelliaIosAppGroupId = 'group.one.dothings.zellia';

/// Must match native widget provider / kind names after you add targets.
const String kAndroidWidgetProviderName = 'ZelliaMemberWidgetProvider';
const String kIosWidgetKindName = 'ZelliaMemberWidget';

const String _kCachedMembersKey = 'cached_widget_members';

/// Multi-member desktop widgets: isolate JSON per elder, maintain id index for native pickers.
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

  /// Push one member snapshot (JSON under `widget_data_$userId`) and refresh timelines.
  Future<void> syncMemberWidgetData(WidgetMemberDto member) async {
    try {
      await HomeWidgetService.initialize();
      final uid = member.userId.trim();
      if (uid.isEmpty) return;
      await HomeWidget.saveWidgetData<String>(
        'widget_data_$uid',
        jsonEncode(member.toJson()),
      );
      final ids = await _readCachedMemberIds();
      ids.add(uid);
      await HomeWidget.saveWidgetData<String>(
        _kCachedMembersKey,
        ids.join(','),
      );
      await HomeWidget.updateWidget(
        name: kAndroidWidgetProviderName,
        iOSName: kIosWidgetKindName,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[HomeWidget] syncMemberWidgetData failed: $e');
        debugPrint('$st');
      }
    }
  }

  /// Unfollow / revoke PRO share: drop widget payload and prune index.
  Future<void> clearMemberWidgetData(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    try {
      await HomeWidgetService.initialize();
      await HomeWidget.saveWidgetData<String>('widget_data_$uid', null);
      final ids = await _readCachedMemberIds();
      ids.remove(uid);
      await HomeWidget.saveWidgetData<String>(
        _kCachedMembersKey,
        ids.isEmpty ? null : ids.join(','),
      );
      await HomeWidget.updateWidget(
        name: kAndroidWidgetProviderName,
        iOSName: kIosWidgetKindName,
      );
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
      final raw = await HomeWidget.getWidgetData<String>('widget_data_$userId');
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
    final medTakenToday = medItems.isEmpty ||
        medItems.every((e) => e.isTaken);
    final updatedAt = _formatUpdatedAt(
      bpRows.isNotEmpty
          ? bpRows.first.measuredAt
          : DateTime.now(),
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
    // Clinic-style threshold for “green vs red” in the widget shell.
    return systolic < 140 && diastolic < 90;
  }

  static String _formatUpdatedAt(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final time = DateFormat('HH:mm').format(local);
    if (sameDay) {
      return '今天 $time';
    }
    return DateFormat('MM-dd HH:mm').format(local);
  }
}

// -----------------------------------------------------------------------------
// Markdown (integration notes for native engineers)
// -----------------------------------------------------------------------------
//
// ### iOS (Swift / WidgetKit)
// - **Read**: use `UserDefaults(suiteName: "group.one.dothings.zellia")` and
//   decode JSON from key `widget_data_<userId>`; list eligible ids from
//   `cached_widget_members` (comma-separated).
// - **Pick member**: prefer **Intent Configuration** / `AppIntent` so the user
//   chooses `userId` in the widget editor; pass the chosen id into the timeline
//   provider and load the matching JSON blob (one timeline per configuration).
// - **Refresh**: `WidgetCenter.shared.reloadTimelines(ofKind: "ZelliaMemberWidget")`
//   mirrors what Flutter triggers via `home_widget`.
//
// ### Android (Kotlin / Glance or RemoteViews)
// - **Read**: `HomeWidgetPlugin` writes into the default widget preference file;
//   mirror keys `widget_data_<userId>` and `cached_widget_members` in your
//   `AppWidgetProvider` / **Glance** `GlanceAppWidget`.
// - **Pick member**: expose a **configuration Activity** or Glance **options
//   sheet** that reads `cached_widget_members`, persists the chosen `userId`
//   in `widget_info`, and loads only that JSON key in `onUpdate`.
// - **Isolation**: never merge elders into one JSON; one key per `userId` keeps
//   updates race-free when multiple widgets are pinned.
//
// -----------------------------------------------------------------------------
