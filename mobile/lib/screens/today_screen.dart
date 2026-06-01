import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_service.dart';
import '../services/local_clinical_store.dart';
import '../services/push_notification_service.dart';
import '../services/sync_manager.dart';
import '../services/voice_reminder_storage_service.dart';
import '../utils/time_utils.dart';
import '../services/pdf_service.dart' as report_pdf;
import '../widgets/family_voice_recorder_sheet.dart';
import 'family_screen.dart';
import 'paywall_screen.dart';
import 'weekly_summary_list_screen.dart';

/// Sentinel for heart-rate dropdown meaning "omit".
const int _kHeartRateSkipValue = -1;

/// BP dialog defaults (常用医学参考值: 120/80 mmHg, 静息心率约 72 bpm).
const int _kBpSystolicDefault = 120;
const int _kBpDiastolicDefault = 80;
const int _kBpHeartRateDefault = 72;
const String _kBsConditionFasting = 'fasting';
const String _kBsConditionPostMeal1h = 'post_meal_1h';
const String _kBsConditionPostMeal2h = 'post_meal_2h';
const String _kBsConditionBedtime = 'bedtime';

/// Poke cooldown from API is 600s; set to 0 while testing reminder flows.
const int kPokeCooldownSecondsForTesting = 0;
const String _kSimpleModePrefsKey = 'zellia_simple_mode_v1';

/// Today: medications list + vitals entry points (see PRD).
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.api, required this.onLogout});

  final ApiService api;
  final Future<void> Function() onLogout;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  List<TodayMedicationItemDto> _todayMeds = [];
  bool _loadingMeds = true;
  bool _medSectionExpanded = true;
  String? _medError;
  BloodPressureRecordDto? _latestBp;
  BloodSugarRecordDto? _latestBs;
  bool _loadingVitals = true;
  String? _vitalsError;
  bool _exportingClinicalReport = false;
  bool _isPremium = false;
  bool _simpleMode = false;
  final Map<int, DateTime> _pokeCooldownUntil = {};
  final Set<int> _pokingPlans = <int>{};
  Timer? _cooldownTicker;
  bool get _isReadOnlyView => currentViewUserId != null;

  // Multi-person swipeable pages
  List<ApprovedElderDto> _approvedElders = [];
  Map<int, BloodPressureRecordDto?> _elderBp = {};
  Map<int, BloodSugarRecordDto?> _elderBs = {};
  final Map<int, bool> _elderVitalsLoading = {};
  Map<int, List<TodayMedicationItemDto>> _elderMeds = {};
  final Map<int, bool> _elderMedsLoading = {};
  int? _myUserId;
  String? _myDisplayName;
  final PageController _healthCardPageController = PageController();
  int _healthCardPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSimpleMode();
    _refreshMedications();
    _refreshVitals();
    _loadUserProfile();
    _loadFamilyElders();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isReadOnlyView) {
      SyncManager.instance.onAppResumed();
      unawaited(_refreshMedications(silent: true));
      unawaited(_refreshVitals());
      unawaited(_loadFamilyElders());
    }
  }

  Future<void> _loadSimpleMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _simpleMode = prefs.getBool(_kSimpleModePrefsKey) ?? false);
  }

  Future<void> _setSimpleMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSimpleModePrefsKey, value);
    if (!mounted) return;
    setState(() => _simpleMode = value);
  }

  Future<void> _loadUserProfile() async {
    try {
      final profile = await widget.api.getCurrentUserProfile();
      if (!mounted) return;
      final nickname = profile.nickname.trim();
      setState(() {
        _isPremium = profile.isPremium;
        _myUserId = profile.id;
        _myDisplayName = nickname.isNotEmpty ? nickname : profile.username.trim();
      });
    } catch (_) {
      if (mounted) setState(() => _isPremium = false);
    }
  }

  Future<void> _loadFamilyElders() async {
    try {
      final elders = await widget.api.getApprovedElders();
      if (!mounted) return;
      setState(() => _approvedElders = elders);
      for (final elder in elders) {
        unawaited(_refreshElderVitals(elder.elderId));
        unawaited(_refreshElderMeds(elder.elderId));
      }
    } catch (_) {}
  }

  Future<void> _refreshElderMeds(int elderId) async {
    if (!mounted) return;
    setState(() => _elderMedsLoading[elderId] = true);
    try {
      final items = await widget.api.getTodayMedications(targetUserId: elderId);
      if (!mounted) return;
      setState(() => _elderMeds[elderId] = items);
    } catch (_) {
      if (mounted) setState(() => _elderMeds[elderId] = []);
    } finally {
      if (mounted) setState(() => _elderMedsLoading.remove(elderId));
    }
  }

  Future<void> _refreshElderVitals(int elderId) async {
    if (!mounted) return;
    setState(() => _elderVitalsLoading[elderId] = true);
    try {
      final bp = await widget.api.getBloodPressureHistory(targetUserId: elderId);
      final bs = await widget.api.getBloodSugarHistory(targetUserId: elderId);
      final now = DateTime.now();
      BloodPressureRecordDto? bpToday;
      for (final item in bp.items) {
        if (_isSameDay(item.measuredAt, now)) {
          bpToday = item;
          break;
        }
      }
      BloodSugarRecordDto? bsToday;
      for (final item in bs.items) {
        if (_isSameDay(item.measuredAt, now)) {
          bsToday = item;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _elderBp[elderId] = bpToday;
        _elderBs[elderId] = bsToday;
      });
    } catch (_) {
      // silently ignore elder vitals load errors
    } finally {
      if (mounted) setState(() => _elderVitalsLoading.remove(elderId));
    }
  }

  Future<void> _openElderBpHistory(int elderId, String name) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFF2FBF8),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFFBCEBDD), width: 1.2),
        ),
        title: Text('$name · ${l10n.bpHistoryTitle}'),
        content: SizedBox(
          width: double.maxFinite,
          child: _PagedHistoryBody<BloodPressureRecordDto>(
            loadPage: (page, pageSize) => widget.api.getBloodPressureHistory(
              page: page,
              pageSize: pageSize,
              targetUserId: elderId,
            ),
            itemIdOf: (item) => item.id,
            deleteItem: (_) async {},
            measuredAtOf: (item) => item.measuredAt,
            rowTextBuilder: (item) {
              final t = TimeUtils.formatLocalDateTime(item.measuredAt, pattern: 'HH:mm');
              final hr = item.heartRate == null ? '' : ' · HR${item.heartRate}';
              return '$t  ${item.systolic}/${item.diastolic}$hr';
            },
            rowTextColorBuilder: (item) => _isBpAbnormal(item)
                ? const Color(0xFFC62828)
                : const Color(0xFF2A5A4E),
            loadErrorText: l10n.vitalsLoadError,
            emptyText: l10n.noRecordsYet,
            dateHeaderBackground: const Color(0xFFE4F7F1),
            dateHeaderBorder: const Color(0xFFA9E3D2),
            dateHeaderTextColor: const Color(0xFF0B5B48),
            rowBackground: const Color(0xFFFAFEFC),
            rowBorder: const Color(0xFFCDEFE5),
            accentColor: const Color(0xFF0E8C72),
            leadingIcon: Icons.favorite_rounded,
            allowDelete: false,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancelLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _openElderBsHistory(int elderId, String name) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFFAF0),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFFFFD28A), width: 1.2),
        ),
        title: Text('$name · ${l10n.bsHistoryTitle}'),
        content: SizedBox(
          width: double.maxFinite,
          child: _PagedHistoryBody<BloodSugarRecordDto>(
            loadPage: (page, pageSize) => widget.api.getBloodSugarHistory(
              page: page,
              pageSize: pageSize,
              targetUserId: elderId,
            ),
            itemIdOf: (item) => item.id,
            deleteItem: (_) async {},
            measuredAtOf: (item) => item.measuredAt,
            rowTextBuilder: (item) {
              final t = TimeUtils.formatLocalDateTime(item.measuredAt, pattern: 'HH:mm');
              final cond = _localizedBsCondition(item.condition, l10n);
              return '$t  ${item.level.toStringAsFixed(1)} mmol/L  $cond';
            },
            rowTextColorBuilder: (_) => const Color(0xFF7B4F00),
            loadErrorText: l10n.vitalsLoadError,
            emptyText: l10n.noRecordsYet,
            dateHeaderBackground: const Color(0xFFFFF8E0),
            dateHeaderBorder: const Color(0xFFFFD28A),
            dateHeaderTextColor: const Color(0xFF7B4F00),
            rowBackground: const Color(0xFFFFFDF5),
            rowBorder: const Color(0xFFFFE5A0),
            accentColor: const Color(0xFFF09000),
            leadingIcon: Icons.water_drop_rounded,
            allowDelete: false,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancelLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _openPro() async {
    if (_isPremium) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const ProBenefitsScreen(),
        ),
      );
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PaywallScreen(api: widget.api),
      ),
    );
    if (!mounted) return;
    await _loadUserProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCooldownTicker();
    _healthCardPageController.dispose();
    super.dispose();
  }

  void _stopCooldownTicker() {
    _cooldownTicker?.cancel();
    _cooldownTicker = null;
  }

  void _syncCooldownTicker() {
    if (_pokeCooldownUntil.isEmpty) {
      _stopCooldownTicker();
      return;
    }
    if (_cooldownTicker != null) return;
    _cooldownTicker = Timer.periodic(
      const Duration(seconds: 1),
      _onCooldownTick,
    );
  }

  void _onCooldownTick(Timer timer) {
    if (!mounted) {
      timer.cancel();
      _cooldownTicker = null;
      return;
    }
    if (_pokeCooldownUntil.isEmpty) {
      _stopCooldownTicker();
      return;
    }
    final now = DateTime.now();
    _pokeCooldownUntil.removeWhere((_, until) => !until.isAfter(now));
    if (_pokeCooldownUntil.isEmpty) {
      _stopCooldownTicker();
    }
    setState(() {});
  }

  Future<void> _refreshMedications({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingMeds = true;
        _medError = null;
      });
    }
    final store = LocalClinicalStore.instance;
    final cacheScope = LocalClinicalStore.medicationCacheScope(currentViewUserId);
    final today = DateTime.now();

    Future<void> applyCachedOrEmpty({required bool clearError}) async {
      final cached = await store.medicationsForDisplay(
        targetUserId: currentViewUserId,
        takenDate: today,
        applyPendingOverrides: !_isReadOnlyView,
      );
      if (!mounted) return;
      setState(() {
        _todayMeds = cached;
        if (clearError) _medError = null;
      });
    }

    try {
      final online = await SyncManager.instance.isDeviceOnline();
      if (!online) {
        await applyCachedOrEmpty(clearError: true);
        return;
      }

      var items = await widget.api.getTodayMedications(
        targetUserId: currentViewUserId,
      );
      final takenDate =
          items.isNotEmpty ? items.first.takenDate : today;
      await store.cacheTodayMedications(
        cacheScope: cacheScope,
        takenDate: takenDate,
        items: items,
      );
      if (!_isReadOnlyView) {
        final pending =
            await store.pendingMedicationOverridesForToday(takenDate);
        items = store.mergeTodayMedications(items, pending);
      }
      if (!mounted) return;
      setState(() {
        _todayMeds = items;
        _medError = null;
      });
      if (!_isReadOnlyView) {
        unawaited(_syncElderVoiceReminders(items));
      }
    } catch (e) {
      if (!mounted) return;
      final cached = await store.loadCachedTodayMedications(
        cacheScope: cacheScope,
        takenDate: today,
      );
      if (cached != null) {
        var items = cached;
        if (!_isReadOnlyView) {
          final pending = await store.pendingMedicationOverridesForToday(today);
          items = store.mergeTodayMedications(items, pending);
        }
        setState(() {
          _todayMeds = items;
          _medError = null;
        });
        return;
      }
      if (!_isReadOnlyView && LocalClinicalStore.isLikelyNetworkError(e)) {
        setState(() {
          _todayMeds = [];
          _medError = null;
        });
        return;
      }
      setState(() => _medError = e.toString());
    } finally {
      if (mounted && !silent) {
        setState(() => _loadingMeds = false);
      }
    }
  }

  /// Elder device: download shared family voice and schedule local reminders.
  Future<void> _syncElderVoiceReminders(List<TodayMedicationItemDto> items) async {
    try {
      final profile = await widget.api.getCurrentUserProfile();
      final ownerUserId = currentViewUserId ?? profile.id;
      final storage = VoiceReminderStorageService.instance;
      String? sharedUrl;
      int? caregiverId;
      for (final item in items) {
        final url = item.voiceUrl?.trim();
        if (url != null && url.isNotEmpty) {
          sharedUrl = url;
          caregiverId = item.familyVoiceCaregiverId;
          break;
        }
      }
      if (sharedUrl != null && caregiverId != null) {
        var downloadUrl = sharedUrl;
        try {
          final signed = await widget.api.getVoiceDownloadUrl(
            userId: ownerUserId,
            caregiverId: caregiverId,
          );
          downloadUrl = signed.downloadUrl;
        } catch (_) {
          // Use voice_url from /medications/today (may already be presigned).
        }
        await storage.ensureDownloaded(
          caregiverUserId: caregiverId,
          elderUserId: ownerUserId,
          voiceUrl: downloadUrl,
        );
        if (Platform.isAndroid) {
          await storage.refreshAndroidNotificationContentUri(
            caregiverUserId: caregiverId,
            elderUserId: ownerUserId,
          );
        }
      }
      await PushNotificationService.instance.medicationScheduler
          .syncFromTodayItems(items, ownerUserId: ownerUserId);
    } catch (e, st) {
      debugPrint('voice reminder sync failed: $e\n$st');
    }
  }

  int? _firstPlanIdForLegacyVoiceApi({int? targetUserId}) {
    final List<TodayMedicationItemDto> items;
    if (targetUserId == null) {
      items = _todayMeds;
    } else {
      items = _elderMeds[targetUserId] ?? const [];
    }
    for (final item in items) {
      return item.planId;
    }
    return null;
  }

  Future<void> _openFamilyVoiceRecorder({
    int? targetUserId,
    String? targetDisplayName,
  }) async {
    final elderId = targetUserId ?? currentViewUserId;
    if (elderId == null) return;

    if (!_isPremium) {
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => PaywallScreen(api: widget.api)),
      );
      return;
    }

    final legacyPlanId = _firstPlanIdForLegacyVoiceApi(targetUserId: elderId);
    if (legacyPlanId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _textForLocale(
              '请先为家人添加至少一条用药计划，再录制亲情语音',
              'Add at least one medication plan for your family member before recording voice',
            ),
          ),
        ),
      );
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final displayName = (targetDisplayName ??
            currentViewUserName ??
            l10n.defaultFamilyMemberDisplayName)
        .trim();

    if (!mounted) return;
    final saved = await FamilyVoiceRecorderSheet.show(
      context,
      api: widget.api,
      targetUserId: elderId,
      memberDisplayName: displayName,
      planIdForLegacyApi: legacyPlanId,
    );
    if (saved == true && mounted) {
      await _refreshElderMeds(elderId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _textForLocale('亲情语音已保存', 'Family voice reminder saved'),
          ),
        ),
      );
    }
  }

  int _medicationItemIndex(TodayMedicationItemDto item) {
    return _todayMeds.indexWhere(
      (e) => e.planId == item.planId && e.scheduledTime == item.scheduledTime,
    );
  }

  TodayMedicationItemDto _medicationItemWithTaken(
    TodayMedicationItemDto item, {
    required bool isTaken,
  }) {
    return TodayMedicationItemDto(
      planId: item.planId,
      name: item.name,
      dosage: item.dosage,
      scheduledTime: item.scheduledTime,
      takenDate: item.takenDate,
      logId: item.logId,
      isTaken: isTaken,
      checkedAt: isTaken ? DateTime.now() : null,
      notifyMissed: item.notifyMissed,
      notifyDelayMinutes: item.notifyDelayMinutes,
      voiceUrl: item.voiceUrl,
    );
  }

  Future<void> _refreshAll() async {
    await _refreshMedications();
    await _refreshVitals();
    await _loadUserProfile();
    unawaited(_loadFamilyElders());
  }

  void _openWeeklySummaryList() {
    final l10n = AppLocalizations.of(context)!;
    final int elderId;
    final String displayName;

    if (currentViewUserId != null) {
      elderId = currentViewUserId!;
      displayName =
          (currentViewUserName ?? l10n.defaultFamilyMemberDisplayName).trim();
    } else if (_healthCardPage > 0 &&
        _healthCardPage - 1 < _approvedElders.length) {
      final elder = _approvedElders[_healthCardPage - 1];
      elderId = elder.elderId;
      final alias = (elder.elderAlias ?? '').trim();
      displayName =
          alias.isNotEmpty ? alias : elder.elderUsername.trim();
    } else if (_myUserId != null) {
      elderId = _myUserId!;
      displayName = (_myDisplayName ?? _textForLocale('我的', 'Mine')).trim();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_textForLocale('正在加载，请稍后再试', 'Still loading, try again')),
        ),
      );
      unawaited(_loadUserProfile());
      return;
    }

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WeeklySummaryListScreen(
          api: widget.api,
          elderId: elderId,
          elderDisplayName: displayName,
        ),
      ),
    );
  }

  Future<void> _exportClinicalReport() async {
    if (_exportingClinicalReport) return;
    setState(() => _exportingClinicalReport = true);
    try {
      final defaultUserName = _textForLocale('用户', 'User');
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ClinicalReportPreviewScreen(
            api: widget.api,
            targetUserId: currentViewUserId,
            fallbackPatientName: (currentViewUserName ?? defaultUserName)
                    .trim()
                    .isEmpty
                ? defaultUserName
                : (currentViewUserName ?? defaultUserName).trim(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    } finally {
      if (mounted) {
        setState(() => _exportingClinicalReport = false);
      }
    }
  }

  Future<void> _toggleMedication(TodayMedicationItemDto item) async {
    if (_isReadOnlyView) {
      _showReadOnlyHint();
      return;
    }
    final index = _medicationItemIndex(item);
    final nextTaken = !item.isTaken;
    final previous = index >= 0 ? _todayMeds[index] : item;
    if (index >= 0) {
      setState(() {
        _todayMeds[index] = _medicationItemWithTaken(item, isTaken: nextTaken);
      });
    }
    try {
      await LocalClinicalStore.instance.saveMedicationLogLocal(
        planId: item.planId,
        takenDate: item.takenDate,
        scheduledTime: item.scheduledTime,
        isTaken: nextTaken,
      );
      unawaited(SyncManager.instance.syncPending());
    } catch (e) {
      if (index >= 0) {
        setState(() => _todayMeds[index] = previous);
      }
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.medicationToggleFailed}: $e')),
      );
    }
  }

  Future<bool> _confirmStopMedication(TodayMedicationItemDto item) async {
    if (_isReadOnlyView) {
      _showReadOnlyHint();
      return false;
    }
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.stopMedicationTitle),
          content: Text(l10n.stopMedicationConfirm(item.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(88, 56),
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              child: Text(l10n.stopMedicationAction),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return false;
    try {
      await widget.api.stopMedicationPlan(item.planId);
      await _refreshMedications(silent: true);
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.stopMedicationFailed}: $e')),
      );
      return false;
    }
  }

  Future<void> _openAddMedicationDialog({
    int? targetUserId,
    String? targetDisplayName,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final effectiveTargetId = targetUserId ?? currentViewUserId;
    final isFamilyTarget = effectiveTargetId != null;
    final nameController = TextEditingController();
    final dosageController = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 7));
    final List<TimeOfDay> times = [const TimeOfDay(hour: 8, minute: 0)];
    bool notifyMissed = true;
    int notifyDelayMinutes = 60;
    final delayOptions = <int>[30, 60, 120];
    String? errorText;
    bool submitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !submitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> pickStartDate() async {
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: startDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setDialogState(() {
                  startDate = picked;
                  if (endDate.isBefore(startDate)) {
                    endDate = startDate;
                  }
                });
              }
            }

            Future<void> pickEndDate() async {
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: endDate.isBefore(startDate) ? startDate : endDate,
                firstDate: startDate,
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setDialogState(() => endDate = picked);
              }
            }

            Future<void> addTime() async {
              final picked = await showTimePicker(
                context: dialogContext,
                initialTime: times.isNotEmpty
                    ? times.last
                    : const TimeOfDay(hour: 8, minute: 0),
              );
              if (picked != null) {
                final duplicate = times.any(
                  (t) => t.hour == picked.hour && t.minute == picked.minute,
                );
                if (!duplicate) {
                  setDialogState(() {
                    times.add(picked);
                    times.sort(
                      (a, b) => (a.hour * 60 + a.minute).compareTo(
                        b.hour * 60 + b.minute,
                      ),
                    );
                  });
                }
              }
            }

            Future<void> submit() async {
              final name = nameController.text.trim();
              final dosage = dosageController.text.trim();
              if (name.isEmpty || dosage.isEmpty || times.isEmpty) {
                setDialogState(() => errorText = l10n.medicationFormInvalid);
                return;
              }
              setDialogState(() {
                submitting = true;
                errorText = null;
              });
              try {
                final timeStrings = times
                    .map(
                      (t) =>
                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                    )
                    .toList();
                await widget.api.createMedicationPlan(
                  MedicationPlanCreateDto(
                    name: name,
                    dosage: dosage,
                    startDate: startDate,
                    endDate: endDate,
                    timesADay: timeStrings,
                    notifyMissed: notifyMissed,
                    notifyDelayMinutes: notifyDelayMinutes,
                  ),
                  targetUserId: effectiveTargetId,
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (effectiveTargetId != null) {
                  await _refreshElderMeds(effectiveTargetId);
                } else {
                  await _refreshMedications(silent: true);
                }
                if (mounted && isFamilyTarget) {
                  final memberDisplayName = (targetDisplayName ??
                          currentViewUserName ??
                          l10n.defaultFamilyMemberDisplayName)
                      .trim();
                  final isZh = Localizations.localeOf(
                    context,
                  ).languageCode.toLowerCase().startsWith('zh');
                  final msg = isZh
                      ? '已成功为$memberDisplayName添加计划'
                      : 'Plan added for $memberDisplayName successfully';
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(msg)));
                }
              } catch (e) {
                setDialogState(() => errorText = e.toString());
              } finally {
                if (mounted) {
                  setDialogState(() => submitting = false);
                }
              }
            }

            return AlertDialog(
              title: Text(
                isFamilyTarget
                    ? _textForLocale('帮 Ta 整理小药盒', 'Organize their pillbox')
                    : l10n.addMedicationTitle,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: l10n.medicationNameLabel,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dosageController,
                      decoration: InputDecoration(
                        labelText: l10n.medicationDosageLabel,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: submitting ? null : pickStartDate,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: Text(
                        '${l10n.startDateLabel}: ${DateFormat('yyyy-MM-dd').format(startDate)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: submitting ? null : pickEndDate,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: Text(
                        '${l10n.endDateLabel}: ${DateFormat('yyyy-MM-dd').format(endDate)}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < times.length; i++)
                          InputChip(
                            label: Text(
                              '${times[i].hour.toString().padLeft(2, '0')}:${times[i].minute.toString().padLeft(2, '0')}',
                            ),
                            onDeleted: submitting
                                ? null
                                : () {
                                    setDialogState(() => times.removeAt(i));
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: submitting ? null : addTime,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.addTimeButton),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: notifyMissed,
                      onChanged: submitting
                          ? null
                          : (v) => setDialogState(() => notifyMissed = v),
                      title: Text(
                        _textForLocale('漏服后通知我', 'Notify me when missed'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: _textForLocale('提醒延迟时间', 'Delay before alert'),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: notifyDelayMinutes,
                          isExpanded: true,
                          style: const TextStyle(
                            fontSize: 20,
                            color: Color(0xFF0C5B49),
                            fontWeight: FontWeight.w600,
                          ),
                          items: delayOptions
                              .map(
                                (minutes) => DropdownMenuItem<int>(
                                  value: minutes,
                                  child: Text(
                                    _textForLocale('$minutes 分钟', '$minutes minutes'),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (submitting || !notifyMissed)
                              ? null
                              : (v) {
                                  if (v != null) {
                                    setDialogState(() => notifyDelayMinutes = v);
                                  }
                                },
                        ),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancelLabel),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 56),
                  ),
                  child: Text(submitting ? l10n.savingLabel : l10n.saveLabel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _refreshVitals() async {
    setState(() {
      _loadingVitals = true;
      _vitalsError = null;
    });
    try {
      final bp = await widget.api.getBloodPressureHistory(
        targetUserId: currentViewUserId,
      );
      final bs = await widget.api.getBloodSugarHistory(
        targetUserId: currentViewUserId,
      );
      final now = DateTime.now();
      BloodPressureRecordDto? bpToday;
      for (final item in bp.items) {
        if (_isSameDay(item.measuredAt, now)) {
          bpToday = item;
          break;
        }
      }
      BloodSugarRecordDto? bsToday;
      for (final item in bs.items) {
        if (_isSameDay(item.measuredAt, now)) {
          bsToday = item;
          break;
        }
      }
      if (!_isReadOnlyView) {
        final localBp =
            await LocalClinicalStore.instance.latestLocalBloodPressureForToday();
        final localBs =
            await LocalClinicalStore.instance.latestLocalBloodSugarForToday();
        final store = LocalClinicalStore.instance;
        if (localBp != null &&
            (bpToday == null ||
                localBp.createdAtLocal.isAfter(bpToday.measuredAt))) {
          bpToday = store.toBloodPressureDto(localBp);
        }
        if (localBs != null &&
            (bsToday == null ||
                localBs.createdAtLocal.isAfter(bsToday.measuredAt))) {
          bsToday = store.toBloodSugarDto(localBs);
        }
      }
      if (!mounted) return;
      setState(() {
        _latestBp = bpToday;
        _latestBs = bsToday;
      });
    } catch (e) {
      if (!_isReadOnlyView) {
        try {
          final store = LocalClinicalStore.instance;
          final localBp = await store.latestLocalBloodPressureForToday();
          final localBs = await store.latestLocalBloodSugarForToday();
          if (!mounted) return;
          setState(() {
            _latestBp = localBp != null
                ? store.toBloodPressureDto(localBp)
                : _latestBp;
            _latestBs =
                localBs != null ? store.toBloodSugarDto(localBs) : _latestBs;
            _vitalsError = (localBp == null && localBs == null)
                ? e.toString()
                : null;
          });
          return;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _vitalsError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingVitals = false);
      }
    }
  }

  bool _isSameDay(DateTime source, DateTime target) {
    final localSource = source.toLocal();
    return localSource.year == target.year &&
        localSource.month == target.month &&
        localSource.day == target.day;
  }

  Future<void> _openBpDialog() async {
    if (_isReadOnlyView) {
      _showReadOnlyHint();
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final systolicOptions = List<int>.generate(191, (i) => 60 + i);
    final diastolicOptions = List<int>.generate(111, (i) => 40 + i);
    final heartRateOptions = List<int>.generate(161, (i) => 40 + i);
    DateTime measuredAt = DateTime.now();
    String? errorText;
    bool submitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !submitting,
      builder: (dialogContext) {
        var systolic = _kBpSystolicDefault;
        var diastolic = _kBpDiastolicDefault;
        var heartRateSelection = _kBpHeartRateDefault;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final dialogTheme = Theme.of(dialogContext);
            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: measuredAt,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setDialogState(() {
                  measuredAt = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    measuredAt.hour,
                    measuredAt.minute,
                  );
                });
              }
            }

            Future<void> submit() async {
              final heartRate = heartRateSelection == _kHeartRateSkipValue
                  ? null
                  : heartRateSelection;
              setDialogState(() {
                submitting = true;
                errorText = null;
              });
              try {
                final row =
                    await LocalClinicalStore.instance.saveBloodPressureLocal(
                  systolic: systolic,
                  diastolic: diastolic,
                  heartRate: heartRate,
                  measuredAt: measuredAt,
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                setState(() {
                  _latestBp = LocalClinicalStore.instance.toBloodPressureDto(
                    row,
                  );
                });
                unawaited(SyncManager.instance.syncPending());
              } catch (e) {
                setDialogState(() => errorText = e.toString());
              } finally {
                if (mounted) setDialogState(() => submitting = false);
              }
            }

            return AlertDialog(
              title: Text(l10n.bpRecordTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.bpSystolicLabel,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: systolic,
                          style: dialogTheme.textTheme.bodyLarge,
                          items: systolicOptions
                              .map(
                                (v) => DropdownMenuItem<int>(
                                  value: v,
                                  child: Text('$v mmHg'),
                                ),
                              )
                              .toList(),
                          onChanged: submitting
                              ? null
                              : (v) {
                                  if (v != null)
                                    setDialogState(() => systolic = v);
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.bpDiastolicLabel,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: diastolic,
                          style: dialogTheme.textTheme.bodyLarge,
                          items: diastolicOptions
                              .map(
                                (v) => DropdownMenuItem<int>(
                                  value: v,
                                  child: Text('$v mmHg'),
                                ),
                              )
                              .toList(),
                          onChanged: submitting
                              ? null
                              : (v) {
                                  if (v != null)
                                    setDialogState(() => diastolic = v);
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.bpHeartRateLabel,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: heartRateSelection,
                          style: dialogTheme.textTheme.bodyLarge,
                          items: [
                            DropdownMenuItem<int>(
                              value: _kHeartRateSkipValue,
                              child: Text(l10n.bpHeartRateSkipOption),
                            ),
                            ...heartRateOptions.map(
                              (v) => DropdownMenuItem<int>(
                                value: v,
                                child: Text('$v bpm'),
                              ),
                            ),
                          ],
                          onChanged: submitting
                              ? null
                              : (v) {
                                  if (v != null)
                                    setDialogState(
                                      () => heartRateSelection = v,
                                    );
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: submitting ? null : pickDate,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: Text(
                        '${l10n.measureDateLabel}: ${DateFormat('yyyy-MM-dd').format(measuredAt)}',
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancelLabel),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 56),
                  ),
                  child: Text(submitting ? l10n.savingLabel : l10n.saveLabel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openBpHistoryDialog() async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFFF2FBF8),
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 28,
          ),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFBCEBDD), width: 1.2),
          ),
          title: Text(l10n.bpHistoryTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: _PagedHistoryBody<BloodPressureRecordDto>(
              loadPage: (page, pageSize) => widget.api.getBloodPressureHistory(
                page: page,
                pageSize: pageSize,
                targetUserId: currentViewUserId,
              ),
              itemIdOf: (item) => item.id,
              deleteItem: (item) =>
                  widget.api.deleteBloodPressureRecord(item.id),
              measuredAtOf: (item) => item.measuredAt,
              rowTextBuilder: (item) {
                final measuredAt = TimeUtils.formatLocalDateTime(
                  item.measuredAt,
                  pattern: 'HH:mm',
                );
                final hr = item.heartRate == null
                    ? ''
                    : ' · HR${item.heartRate}';
                return '$measuredAt  ${item.systolic}/${item.diastolic}$hr';
              },
              rowTextColorBuilder: (item) => _isBpAbnormal(item)
                  ? const Color(0xFFC62828)
                  : const Color(0xFF2A5A4E),
              loadErrorText: l10n.vitalsLoadError,
              emptyText: l10n.noRecordsYet,
              dateHeaderBackground: const Color(0xFFE4F7F1),
              dateHeaderBorder: const Color(0xFFA9E3D2),
              dateHeaderTextColor: const Color(0xFF0B5B48),
              rowBackground: const Color(0xFFFAFEFC),
              rowBorder: const Color(0xFFCDEFE5),
              accentColor: const Color(0xFF169679),
              leadingIcon: Icons.monitor_heart_outlined,
              allowDelete: !_isReadOnlyView,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancelLabel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openBsDialog() async {
    if (_isReadOnlyView) {
      _showReadOnlyHint();
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final levelController = TextEditingController();
    final conditions = [
      (_kBsConditionFasting, l10n.bsConditionFasting),
      (_kBsConditionPostMeal1h, l10n.bsConditionPostMeal1h),
      (_kBsConditionPostMeal2h, l10n.bsConditionPostMeal2h),
      (_kBsConditionBedtime, l10n.bsConditionBedtime),
    ];
    String selectedConditionCode = _kBsConditionFasting;
    DateTime measuredAt = DateTime.now();
    String? errorText;
    bool submitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !submitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: measuredAt,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setDialogState(() {
                  measuredAt = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    measuredAt.hour,
                    measuredAt.minute,
                  );
                });
              }
            }

            Future<void> submit() async {
              final level = double.tryParse(levelController.text.trim());
              if (level == null) {
                setDialogState(() => errorText = l10n.vitalsInvalidNumber);
                return;
              }
              setDialogState(() {
                submitting = true;
                errorText = null;
              });
              try {
                final row = await LocalClinicalStore.instance.saveBloodSugarLocal(
                  level: level,
                  condition: selectedConditionCode,
                  measuredAt: measuredAt,
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                setState(() {
                  _latestBs = LocalClinicalStore.instance.toBloodSugarDto(row);
                });
                unawaited(SyncManager.instance.syncPending());
              } catch (e) {
                setDialogState(() => errorText = e.toString());
              } finally {
                if (mounted) setDialogState(() => submitting = false);
              }
            }

            return AlertDialog(
              title: Text(l10n.bsRecordTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: levelController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(labelText: l10n.bsLevelLabel),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: conditions
                          .map(
                            (item) => ChoiceChip(
                              label: Text(item.$2),
                              selected: selectedConditionCode == item.$1,
                              onSelected: submitting
                                  ? null
                                  : (_) => setDialogState(
                                      () => selectedConditionCode = item.$1,
                                    ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: submitting ? null : pickDate,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: Text(
                        '${l10n.measureDateLabel}: ${DateFormat('yyyy-MM-dd').format(measuredAt)}',
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancelLabel),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 56),
                  ),
                  child: Text(submitting ? l10n.savingLabel : l10n.saveLabel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openBsHistoryDialog() async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFFF5FCFA),
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 28,
          ),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFBEECDD), width: 1.2),
          ),
          title: Text(l10n.bsHistoryTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: _PagedHistoryBody<BloodSugarRecordDto>(
              loadPage: (page, pageSize) => widget.api.getBloodSugarHistory(
                page: page,
                pageSize: pageSize,
                targetUserId: currentViewUserId,
              ),
              itemIdOf: (item) => item.id,
              deleteItem: (item) => widget.api.deleteBloodSugarRecord(item.id),
              measuredAtOf: (item) => item.measuredAt,
              rowTextBuilder: (item) {
                final measuredAt = TimeUtils.formatLocalDateTime(
                  item.measuredAt,
                  pattern: 'HH:mm',
                );
                final localizedCondition = _localizedBsCondition(
                  item.condition,
                  l10n,
                );
                return '$measuredAt  ${item.level.toStringAsFixed(1)} · $localizedCondition';
              },
              rowTextColorBuilder: (item) => _isBsAbnormal(item)
                  ? const Color(0xFFC62828)
                  : const Color(0xFF2A5A4E),
              loadErrorText: l10n.vitalsLoadError,
              emptyText: l10n.noRecordsYet,
              dateHeaderBackground: const Color(0xFFE8F8F3),
              dateHeaderBorder: const Color(0xFFADE4D4),
              dateHeaderTextColor: const Color(0xFF116250),
              rowBackground: const Color(0xFFFBFEFD),
              rowBorder: const Color(0xFFD2F0E8),
              accentColor: const Color(0xFF1DA988),
              leadingIcon: Icons.water_drop_outlined,
              allowDelete: !_isReadOnlyView,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancelLabel),
            ),
          ],
        );
      },
    );
  }

  String _bpSubtitle(AppLocalizations l10n) {
    if (_loadingVitals) return l10n.loading;
    if (_vitalsError != null) return l10n.vitalsLoadError;
    if (_latestBp == null) return l10n.noRecordsToday;
    final hr = _latestBp!.heartRate == null
        ? ''
        : ' • ${_latestBp!.heartRate} bpm';
    final measuredAt = TimeUtils.formatLocalDateTime(
      _latestBp!.measuredAt,
      pattern: 'HH:mm',
    );
    return '$measuredAt • ${_latestBp!.systolic}/${_latestBp!.diastolic} mmHg$hr';
  }

  String _bsSubtitle(AppLocalizations l10n) {
    if (_loadingVitals) return l10n.loading;
    if (_vitalsError != null) return l10n.vitalsLoadError;
    if (_latestBs == null) return l10n.noRecordsToday;
    final measuredAt = TimeUtils.formatLocalDateTime(
      _latestBs!.measuredAt,
      pattern: 'HH:mm',
    );
    final localizedCondition = _localizedBsCondition(
      _latestBs!.condition,
      l10n,
    );
    return '$measuredAt • ${_latestBs!.level.toStringAsFixed(1)} mmol/L • $localizedCondition';
  }

  String _localizedBsCondition(String raw, AppLocalizations l10n) {
    switch (raw) {
      case _kBsConditionFasting:
      case '空腹':
      case 'Fasting':
        return l10n.bsConditionFasting;
      case _kBsConditionPostMeal1h:
      case '餐后1h':
      case 'Post-meal 1h':
        return l10n.bsConditionPostMeal1h;
      case _kBsConditionPostMeal2h:
      case '餐后2h':
      case 'Post-meal 2h':
        return l10n.bsConditionPostMeal2h;
      case _kBsConditionBedtime:
      case '睡前':
      case 'Before bed':
        return l10n.bsConditionBedtime;
      default:
        return raw;
    }
  }

  String _bpTextFor(BloodPressureRecordDto? bp, AppLocalizations l10n) {
    if (bp == null) return l10n.noRecordsToday;
    final hr = bp.heartRate == null ? '' : ' • ${bp.heartRate} bpm';
    final measuredAt = TimeUtils.formatLocalDateTime(bp.measuredAt, pattern: 'HH:mm');
    return '$measuredAt  ${bp.systolic}/${bp.diastolic} mmHg$hr';
  }

  String _bsTextFor(BloodSugarRecordDto? bs, AppLocalizations l10n) {
    if (bs == null) return l10n.noRecordsToday;
    final measuredAt = TimeUtils.formatLocalDateTime(bs.measuredAt, pattern: 'HH:mm');
    final condition = _localizedBsCondition(bs.condition, l10n);
    return '$measuredAt  ${bs.level.toStringAsFixed(1)} mmol/L  $condition';
  }

  bool _isBpAbnormal(BloodPressureRecordDto item) {
    final bpAbnormal =
        item.systolic < 90 ||
        item.systolic > 140 ||
        item.diastolic < 60 ||
        item.diastolic > 90;
    final hrAbnormal =
        item.heartRate != null &&
        (item.heartRate! < 50 || item.heartRate! > 100);
    return bpAbnormal || hrAbnormal;
  }

  bool _isBsAbnormal(BloodSugarRecordDto item) {
    final level = item.level;
    // Unified clinical ranges:
    // - Fasting normal: 3.9-5.4 mmol/L
    // - Post-meal (use 2h reference): normal < 7.8 mmol/L
    // - Bedtime: usually < 8.0 mmol/L
    if (level < 3.9) return true;
    switch (item.condition) {
      case _kBsConditionFasting:
      case '空腹':
      case 'Fasting':
        return level > 5.4;
      case _kBsConditionPostMeal1h:
      case _kBsConditionPostMeal2h:
      case '餐后1h':
      case '餐后2h':
      case 'Post-meal 1h':
      case 'Post-meal 2h':
        return level >= 7.8;
      case _kBsConditionBedtime:
      case '睡前':
      case 'Before bed':
        return level >= 8.0;
      default:
        return level >= 10.0;
    }
  }

  DateTime _scheduledAtLocal(TodayMedicationItemDto item) {
    final parts = item.scheduledTime.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final localDate = item.takenDate.toLocal();
    return DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
      hour,
      minute,
    );
  }

  bool _isOverdueAndUncheck(TodayMedicationItemDto item) {
    if (item.isTaken || !item.notifyMissed) return false;
    final triggerAt = _scheduledAtLocal(item).add(
      Duration(minutes: item.notifyDelayMinutes),
    );
    return DateTime.now().isAfter(triggerAt);
  }

  int _cooldownLeftSeconds(int planId) {
    final until = _pokeCooldownUntil[planId];
    if (until == null) return 0;
    final left = until.difference(DateTime.now()).inSeconds;
    if (left <= 0) {
      _pokeCooldownUntil.remove(planId);
      return 0;
    }
    return left;
  }

  Future<void> _pokeFamilyMember(TodayMedicationItemDto item) async {
    final planId = item.planId;
    if (_pokingPlans.contains(planId)) return;
    if (kPokeCooldownSecondsForTesting == 0) {
      _pokeCooldownUntil.remove(planId);
    } else if (_cooldownLeftSeconds(planId) > 0) {
      return;
    }
    setState(() => _pokingPlans.add(planId));
    try {
      final res = await widget.api.pokeElder(
        planId,
        skipCooldown: kPokeCooldownSecondsForTesting == 0,
      );
      if (!mounted) return;
      final ok = (res['ok'] as bool?) ?? true;
      final cooldown = kPokeCooldownSecondsForTesting > 0
          ? (kPokeCooldownSecondsForTesting)
          : ((res['cooldown_seconds'] as int?) ?? 600);
      if (cooldown > 0) {
        setState(() {
          _pokeCooldownUntil[planId] = DateTime.now().add(
            Duration(seconds: cooldown),
          );
        });
        _syncCooldownTicker();
      }
      final msg = ok
          ? _textForLocale(
              '✅ 悄悄的提醒已发送，希望 Ta 能快点吃药！',
              '✅ Gentle nudge sent. Hopefully, they\'ll take it soon!',
            )
          : _textForLocale('提醒过于频繁，请稍后再试', 'Reminder is cooling down');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_textForLocale('提醒失败', 'Reminder failed')}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _pokingPlans.remove(planId));
      }
    }
  }

  void _showReadOnlyHint() {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.readOnlyFamilyMemberModeHint)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    const warmBackground = Color(0xFFF5FCFA);
    return Scaffold(
      backgroundColor: warmBackground,
      appBar: AppBar(
        title: Text(l10n.todayTitle),
        bottom: _approvedElders.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFD0EDE6), width: 1),
                    ),
                  ),
                  child: SizedBox(
                    height: 44,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      itemCount: 1 + _approvedElders.length,
                      itemBuilder: (_, i) {
                        final isActive = i == _healthCardPage;
                        final name = i == 0
                            ? (_myDisplayName ??
                                _textForLocale('我的', 'Mine'))
                            : (() {
                                final e = _approvedElders[i - 1];
                                return (e.elderAlias ?? '').trim().isNotEmpty
                                    ? e.elderAlias!.trim()
                                    : e.elderUsername;
                              })();
                        return GestureDetector(
                          onTap: () => _healthCardPageController.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 0,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF0E6A55)
                                  : const Color(0xFFDEF0EB),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Center(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isActive
                                      ? Colors.white
                                      : const Color(0xFF3A6B5E),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
        actions: [
          if (!_simpleMode) ...[
            IconButton(
              tooltip: _isPremium
                  ? _textForLocale('PRO 权益', 'PRO benefits')
                  : _textForLocale('升级 PRO', 'Upgrade to PRO'),
              onPressed: _openPro,
              icon: const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFFC9A227),
              ),
            ),
            IconButton(
              tooltip: l10n.weeklySummaryListTitle,
              onPressed: _openWeeklySummaryList,
              icon: const Icon(Icons.insights_outlined),
            ),
            IconButton(
              tooltip: _textForLocale('导出给医生', 'Export for doctor'),
              onPressed: _exportingClinicalReport ? null : _exportClinicalReport,
              icon: _exportingClinicalReport
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.picture_as_pdf),
            ),
          ],
          IconButton(
            tooltip: _textForLocale('家人守护', 'Family care'),
            icon: const Icon(Icons.family_restroom),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FamilyScreen(
                    api: widget.api,
                    onLogout: widget.onLogout,
                    simpleMode: _simpleMode,
                  ),
                ),
              );
              if (!mounted) return;
              await _loadSimpleMode();
              await _refreshAll();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _healthCardPageController,
              onPageChanged: (i) => setState(() => _healthCardPage = i),
              children: [
                // ── Page 0: my own data ──
                _buildMyPage(context, l10n, theme),
                // ── Pages 1+: each family member ──
                ..._approvedElders.map(
                  (elder) => _buildElderPage(context, l10n, theme, elder),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Page 0 – current user's own medications + vitals.
  Widget _buildMyPage(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    const medicationPanelTop = Color(0xFFDFF7EF);
    const medicationPanelBottom = Color(0xFFEFFCF7);
    const medicationAccent = Color(0xFF18A686);
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SimpleModeSwitchCard(
            value: _simpleMode,
            onChanged: _setSimpleMode,
            title: _textForLocale('极简模式', 'Simple mode'),
            subtitle: _textForLocale(
              '开启后，右上角只保留家人守护入口',
              'Keep only family care in the top right.',
            ),
          ),
          const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [medicationPanelTop, medicationPanelBottom],
                ),
                border: Border.all(color: const Color(0xFFA9E3D2), width: 1.2),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () =>
                    setState(() => _medSectionExpanded = !_medSectionExpanded),
                child: Row(
                  children: [
                    const Icon(
                      Icons.medication_rounded,
                      color: medicationAccent,
                      size: 30,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.medicationSectionTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: const Color(0xFF0C5B49),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      _medSectionExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: const Color(0xFF0C5B49),
                      size: 30,
                    ),
                  ],
                ),
              ),
            ),
            if (_medSectionExpanded) ...[
              const SizedBox(height: 10),
              if (_loadingMeds)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_medError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _medError!,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (_todayMeds.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    l10n.noMedicationToday,
                    style: theme.textTheme.bodyLarge,
                  ),
                )
              else
                ..._todayMeds.map((item) {
                  final showPokeButton = _isReadOnlyView && _isOverdueAndUncheck(item);
                  final cooldownLeft = kPokeCooldownSecondsForTesting > 0
                      ? _cooldownLeftSeconds(item.planId)
                      : 0;
                  final isPoking = _pokingPlans.contains(item.planId);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Slidable(
                        key: ValueKey('med-${item.planId}-${item.scheduledTime}'),
                        enabled: !_isReadOnlyView,
                        closeOnScroll: true,
                        endActionPane: _isReadOnlyView
                            ? null
                            : ActionPane(
                                motion: const BehindMotion(),
                                extentRatio: 1 / 3,
                                children: [
                                  CustomSlidableAction(
                                    onPressed: (_) async {
                                      await _confirmStopMedication(item);
                                    },
                                    backgroundColor: theme.colorScheme.error,
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Icon(
                                      Icons.delete,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                ],
                              ),
                        child: Card(
                        clipBehavior: Clip.antiAlias,
                        color: item.isTaken
                            ? const Color(0xFFEAF8E8)
                            : Colors.white,
                        elevation: item.isTaken ? 0.5 : 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: item.isTaken
                                ? const Color(0xFF9FD7A4)
                                : const Color(0xFF9EDFCC),
                            width: 1.1,
                          ),
                        ),
                        child: Opacity(
                          opacity: _isReadOnlyView ? 0.62 : 1,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _isReadOnlyView
                                ? null
                                : () => _toggleMedication(item),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 56),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: theme.textTheme.titleLarge,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${item.dosage} • ${item.scheduledTime}',
                                          style: theme.textTheme.bodyLarge,
                                        ),
                                        if (item.isTaken &&
                                            item.checkedAt != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            l10n.medicationCheckedAt(
                                              DateFormat('HH:mm').format(
                                                item.checkedAt!,
                                              ),
                                            ),
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: Colors.green.shade800,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (showPokeButton)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: FilledButton.icon(
                                            onPressed: (cooldownLeft > 0 || isPoking)
                                                ? null
                                                : () => _pokeFamilyMember(item),
                                            style: FilledButton.styleFrom(
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              visualDensity: VisualDensity.compact,
                                              backgroundColor: const Color(0xFFE65100),
                                              disabledBackgroundColor: const Color(0xFFB7B7B7),
                                              foregroundColor: Colors.white,
                                              textStyle: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            icon: isPoking
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2.2,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : const Text(
                                                    '🔔',
                                                    style: TextStyle(fontSize: 15),
                                                  ),
                                            label: Text(
                                              cooldownLeft > 0
                                                  ? _textForLocale(
                                                      '${cooldownLeft}s',
                                                      '${cooldownLeft}s',
                                                    )
                                                  : _textForLocale(
                                                      '悄悄提醒 Ta 一下',
                                                      'Send a gentle nudge',
                                                    ),
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              softWrap: true,
                                            ),
                                          ),
                                        ),
                                      Icon(
                                        item.isTaken
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank,
                                        size: 34,
                                        color: _isReadOnlyView
                                            ? const Color(0xFF84A69B)
                                            : (item.isTaken
                                                  ? Colors.green.shade700
                                                  : medicationAccent),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      ),
                    ),
                  );
                }),
              if (_isReadOnlyView) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openFamilyVoiceRecorder(),
                  icon: const Text('🎙️'),
                  label: Text(
                    _textForLocale(
                      '留一条语音叮嘱',
                      'Leave a voice note',
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: const Color(0xFF0E6A55),
                    side: const BorderSide(color: Color(0xFF9BDDCB)),
                    backgroundColor: const Color(0xFFF0FBF7),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _openAddMedicationDialog(),
                icon: _isReadOnlyView
                    ? const Text(
                        '➕',
                        style: TextStyle(fontSize: 20),
                      )
                    : const Icon(Icons.add),
                label: Text(
                  _isReadOnlyView
                      ? _textForLocale('帮 Ta 整理小药盒', 'Organize their pillbox')
                      : l10n.addMedicationTitle,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  foregroundColor: const Color(0xFF0E6A55),
                  side: const BorderSide(color: Color(0xFF9BDDCB)),
                  backgroundColor: const Color(0xFFF0FBF7),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(l10n.vitalsSectionTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            _MyHealthCard(
              displayName: _myDisplayName ?? _textForLocale('我的数据', 'My Data'),
              bpSubtitle: _bpSubtitle(l10n),
              bsSubtitle: _bsSubtitle(l10n),
              bpButtonLabel: l10n.recordBloodPressure,
              bsButtonLabel: l10n.recordBloodSugar,
              loading: _loadingVitals,
              onBpTap: _openBpHistoryDialog,
              onBsTap: _openBsHistoryDialog,
              onBpRecord: _openBpDialog,
              onBsRecord: _openBsDialog,
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
  }

  /// Page 1+ – a family member's medications + vitals (read-only).
  Widget _buildElderPage(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    ApprovedElderDto elder,
  ) {
    final elderId = elder.elderId;
    final name = (elder.elderAlias ?? '').trim().isNotEmpty
        ? elder.elderAlias!.trim()
        : elder.elderUsername;
    final medsLoading = _elderMedsLoading[elderId] ?? false;
    final meds = _elderMeds[elderId] ?? [];
    final vitalsLoading = _elderVitalsLoading[elderId] ?? false;
    final bp = _elderBp[elderId];
    final bs = _elderBs[elderId];
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _refreshElderMeds(elderId),
          _refreshElderVitals(elderId),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Medication section (read-only) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFDFF7EF), Color(0xFFEFFCF7)],
              ),
              border: Border.all(color: const Color(0xFFA9E3D2), width: 1.2),
            ),
            child: Row(
              children: [
                const Icon(Icons.medication_rounded, color: Color(0xFF18A686), size: 26),
                const SizedBox(width: 8),
                Text(
                  l10n.medicationSectionTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF0C5B49),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (medsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (meds.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.noMedicationToday, style: theme.textTheme.bodyLarge),
            )
          else
            ...meds.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  color: item.isTaken ? const Color(0xFFEAF8E8) : Colors.white,
                  elevation: item.isTaken ? 0.5 : 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: item.isTaken
                          ? const Color(0xFF9FD7A4)
                          : const Color(0xFF9EDFCC),
                      width: 1.1,
                    ),
                  ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: theme.textTheme.titleLarge),
                              const SizedBox(height: 4),
                              Text(
                                '${item.dosage} · ${item.scheduledTime}',
                                style: theme.textTheme.bodyLarge,
                              ),
                              if (item.isTaken && item.checkedAt != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  l10n.medicationCheckedAt(
                                    DateFormat('HH:mm').format(item.checkedAt!),
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          item.isTaken
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 30,
                          color: item.isTaken
                              ? Colors.green.shade600
                              : const Color(0xFFBBBBBB),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _openAddMedicationDialog(
              targetUserId: elderId,
              targetDisplayName: name,
            ),
            icon: const Text('➕', style: TextStyle(fontSize: 20)),
            label: Text(
              _textForLocale('帮 Ta 整理小药盒', 'Organize their pillbox'),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: const Color(0xFF0E6A55),
              side: const BorderSide(color: Color(0xFF9BDDCB)),
              backgroundColor: const Color(0xFFF0FBF7),
            ),
          ),
          // ── Vitals section (read-only) ──
          const SizedBox(height: 24),
          Text(l10n.vitalsSectionTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _ElderHealthCard(
            displayName: name,
            avatarUrl: elder.elderAvatarUrl,
            bpText: vitalsLoading ? l10n.loading : _bpTextFor(bp, l10n),
            bsText: vitalsLoading ? l10n.loading : _bsTextFor(bs, l10n),
            loading: vitalsLoading,
            onBpHistoryTap: () => _openElderBpHistory(elderId, name),
            onBsHistoryTap: () => _openElderBsHistory(elderId, name),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _textForLocale(String zh, String en) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    return lang.startsWith('zh') ? zh : en;
  }
}


class _SimpleModeSwitchCard extends StatelessWidget {
  const _SimpleModeSwitchCard({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD7EAE4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.spa_outlined, color: Color(0xFF0E6A55), size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF163F35),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      color: Color(0xFF58736B),
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _ClinicalReportPreviewScreen extends StatefulWidget {
  const _ClinicalReportPreviewScreen({
    required this.api,
    required this.targetUserId,
    required this.fallbackPatientName,
  });

  final ApiService api;
  final int? targetUserId;
  final String fallbackPatientName;

  @override
  State<_ClinicalReportPreviewScreen> createState() =>
      _ClinicalReportPreviewScreenState();
}

class _ClinicalReportPreviewScreenState extends State<_ClinicalReportPreviewScreen> {
  Uint8List? _pdfBytes;
  String? _patientName;
  bool _loading = true;
  bool _sharing = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _text(String zh, String en) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    return lang.startsWith('zh') ? zh : en;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reportData = await widget.api.getClinicalSummaryReport(
        days: 30,
        targetUserId: widget.targetUserId,
      );
      final patientMap =
          (reportData['patient'] as Map<String, dynamic>? ?? const {});
      final nickname = (patientMap['nickname'] as String?)?.trim();
      final username = (patientMap['username'] as String?)?.trim();
      final patientName = (nickname != null && nickname.isNotEmpty)
          ? nickname
          : ((username != null && username.isNotEmpty)
                ? username
                : widget.fallbackPatientName);
      final languageCode = Localizations.localeOf(context).languageCode;
      final bytes = await report_pdf.buildClinicalReportPdfBytes(
        reportData,
        patientName,
        languageCode: languageCode,
      );
      if (!mounted) return;
      setState(() {
        _pdfBytes = bytes;
        _patientName = patientName;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _share() async {
    final bytes = _pdfBytes;
    if (bytes == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      await report_pdf.shareClinicalReportBytes(
        bytes,
        _patientName ?? widget.fallbackPatientName,
        languageCode: Localizations.localeOf(context).languageCode,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('分享失败: $e', 'Share failed: $e'))),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _save() async {
    final bytes = _pdfBytes;
    if (bytes == null || _saving) return;
    setState(() => _saving = true);
    try {
      final path = await report_pdf.saveClinicalReportToDevice(
        bytes,
        _patientName ?? widget.fallbackPatientName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('已保存到手机: $path', 'Saved to device: $path')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('保存失败: $e', 'Save failed: $e'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_text('医疗报表预览', 'Report Preview')),
      ),
      backgroundColor: const Color(0xFFEAF8F2),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: const Color(0xFF0E6A55),
                      backgroundColor: const Color(0xFFCDEFE2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _text('正在为您汇总健康数据...', 'Summarizing health data...'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0E6A55),
                    ),
                  ),
                ],
              ),
            )
          : (_error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _text('报表加载失败: $_error', 'Failed to load report: $_error'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFB00020),
                            ),
                          ),
                          if (_error!.contains('PRO')) ...[
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: () async {
                                await Navigator.of(context).push<bool>(
                                  MaterialPageRoute<bool>(
                                    builder: (_) => PaywallScreen(api: widget.api),
                                  ),
                                );
                                if (!context.mounted) return;
                                await _load();
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0E6A55),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(50),
                              ),
                              icon: const Icon(Icons.workspace_premium_rounded),
                              label: Text(
                                _text('了解 PRO 订阅', 'View PRO plans'),
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : PdfPreview(
                    build: (_) async => _pdfBytes!,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowPrinting: false,
                    allowSharing: false,
                  )),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _pdfBytes == null
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FloatingActionButton.extended(
                      heroTag: 'report-share-fab',
                      backgroundColor: const Color(0xFF0E6A55),
                      onPressed: _sharing ? null : _share,
                      icon: _sharing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.share_rounded),
                      label: Text(
                        _text('分享给医生（微信/邮件）', 'Share to doctor'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FloatingActionButton.extended(
                      heroTag: 'report-save-fab',
                      backgroundColor: const Color(0xFF2E8B74),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(_text('保存到手机', 'Save to device')),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Card showing the current user's own health data with record buttons.
class _MyHealthCard extends StatelessWidget {
  const _MyHealthCard({
    required this.displayName,
    required this.bpSubtitle,
    required this.bsSubtitle,
    required this.bpButtonLabel,
    required this.bsButtonLabel,
    required this.loading,
    required this.onBpTap,
    required this.onBsTap,
    required this.onBpRecord,
    required this.onBsRecord,
  });

  final String displayName;
  final String bpSubtitle;
  final String bsSubtitle;
  final String bpButtonLabel;
  final String bsButtonLabel;
  final bool loading;
  final VoidCallback onBpTap;
  final VoidCallback onBsTap;
  final VoidCallback onBpRecord;
  final VoidCallback onBsRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE6F8F1), Color(0xFFF4FDF9)],
        ),
        border: Border.all(color: const Color(0xFFA9E3D2), width: 1.3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // BP row
          InkWell(
            onTap: onBpTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.favorite_rounded,
                        size: 18,
                        color: Color(0xFFE57373),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.bloodPressureTitle,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF8C4B00),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Colors.grey.shade400,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text(
                      loading ? '…' : bpSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5A3500),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: OutlinedButton.icon(
              onPressed: onBpRecord,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
                foregroundColor: const Color(0xFF0E6A55),
                side: const BorderSide(color: Color(0xFF7DCAB8), width: 1.2),
                backgroundColor: const Color(0xFFF0FBF7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(bpButtonLabel),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFCCEFE6)),
          // BS row
          InkWell(
            onTap: onBsTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.water_drop_rounded,
                        size: 18,
                        color: Color(0xFFF09000),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.bloodSugarTitle,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF9E6B00),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Colors.grey.shade400,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text(
                      loading ? '…' : bsSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF7B4F00),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: OutlinedButton.icon(
              onPressed: onBsRecord,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
                foregroundColor: const Color(0xFF0E6A55),
                side: const BorderSide(color: Color(0xFF7DCAB8), width: 1.2),
                backgroundColor: const Color(0xFFF0FBF7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(bsButtonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card showing a monitored family member's health data (read-only).
class _ElderHealthCard extends StatelessWidget {
  const _ElderHealthCard({
    required this.displayName,
    required this.avatarUrl,
    required this.bpText,
    required this.bsText,
    required this.loading,
    required this.onBpHistoryTap,
    required this.onBsHistoryTap,
  });

  final String displayName;
  final String? avatarUrl;
  final String bpText;
  final String bsText;
  final bool loading;
  final VoidCallback onBpHistoryTap;
  final VoidCallback onBsHistoryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD8EDE7), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // BP row
          InkWell(
            onTap: onBpHistoryTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    size: 17,
                    color: Color(0xFFE57373),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.bloodPressureTitle,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: const Color(0xFF8C4B00),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          bpText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF5A3500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFEEF7F4)),
          // BS row
          InkWell(
            onTap: onBsHistoryTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.water_drop_rounded,
                    size: 17,
                    color: Color(0xFFF09000),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.bloodSugarTitle,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: const Color(0xFF9E6B00),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          bsText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF7B4F00),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PagedHistoryBody<T> extends StatefulWidget {
  const _PagedHistoryBody({
    required this.loadPage,
    required this.itemIdOf,
    required this.deleteItem,
    required this.measuredAtOf,
    required this.rowTextBuilder,
    required this.rowTextColorBuilder,
    required this.loadErrorText,
    required this.emptyText,
    required this.dateHeaderBackground,
    required this.dateHeaderBorder,
    required this.dateHeaderTextColor,
    required this.rowBackground,
    required this.rowBorder,
    required this.accentColor,
    required this.leadingIcon,
    this.allowDelete = true,
  });

  final Future<VitalsHistoryPage<T>> Function(int page, int pageSize) loadPage;
  final int Function(T item) itemIdOf;
  final Future<void> Function(T item) deleteItem;
  final DateTime Function(T item) measuredAtOf;
  final String Function(T item) rowTextBuilder;
  final Color Function(T item) rowTextColorBuilder;
  final String loadErrorText;
  final String emptyText;
  final Color dateHeaderBackground;
  final Color dateHeaderBorder;
  final Color dateHeaderTextColor;
  final Color rowBackground;
  final Color rowBorder;
  final Color accentColor;
  final IconData leadingIcon;
  final bool allowDelete;

  @override
  State<_PagedHistoryBody<T>> createState() => _PagedHistoryBodyState<T>();
}

class _PagedHistoryBodyState<T> extends State<_PagedHistoryBody<T>> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  final List<T> _records = [];
  int _nextPage = 1;
  int _total = 0;
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadNextPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        !_hasMore ||
        _isLoadingMore ||
        _isInitialLoading)
      return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 120) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _error = null;
      if (_records.isEmpty) {
        _isInitialLoading = true;
      } else {
        _isLoadingMore = true;
      }
    });
    try {
      final page = await widget.loadPage(_nextPage, _pageSize);
      if (!mounted) return;
      setState(() {
        _records.addAll(page.items);
        _total = page.total;
        _nextPage += 1;
        _hasMore = _records.length < _total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_records.isEmpty && _error != null) {
      return Text(
        widget.loadErrorText,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    if (_records.isEmpty) return Text(widget.emptyText);

    return _HistoryGroupedList<T>(
      records: _records,
      itemIdOf: widget.itemIdOf,
      onDelete: (item) async {
        if (!widget.allowDelete) return false;
        try {
          await widget.deleteItem(item);
          _records.removeWhere(
            (r) => widget.itemIdOf(r) == widget.itemIdOf(item),
          );
          if (_total > 0) {
            _total -= 1;
          }
          _hasMore = _records.length < _total;
          if (mounted) {
            setState(() {});
          }
          return true;
        } catch (_) {
          return false;
        }
      },
      measuredAtOf: widget.measuredAtOf,
      rowTextBuilder: widget.rowTextBuilder,
      rowTextColorBuilder: widget.rowTextColorBuilder,
      dateHeaderBackground: widget.dateHeaderBackground,
      dateHeaderBorder: widget.dateHeaderBorder,
      dateHeaderTextColor: widget.dateHeaderTextColor,
      rowBackground: widget.rowBackground,
      rowBorder: widget.rowBorder,
      accentColor: widget.accentColor,
      leadingIcon: widget.leadingIcon,
      allowDelete: widget.allowDelete,
      controller: _scrollController,
      footer: _isLoadingMore
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          : (_error != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(
                      onPressed: _loadNextPage,
                      child: Text(widget.loadErrorText),
                    ),
                  )
                : const SizedBox.shrink()),
    );
  }
}

class _HistoryGroupedList<T> extends StatelessWidget {
  const _HistoryGroupedList({
    required this.records,
    required this.itemIdOf,
    required this.onDelete,
    required this.measuredAtOf,
    required this.rowTextBuilder,
    required this.rowTextColorBuilder,
    required this.dateHeaderBackground,
    required this.dateHeaderBorder,
    required this.dateHeaderTextColor,
    required this.rowBackground,
    required this.rowBorder,
    required this.accentColor,
    required this.leadingIcon,
    this.allowDelete = true,
    this.controller,
    this.footer,
  });

  final List<T> records;
  final int Function(T item) itemIdOf;
  final Future<bool> Function(T item) onDelete;
  final DateTime Function(T item) measuredAtOf;
  final String Function(T item) rowTextBuilder;
  final Color Function(T item) rowTextColorBuilder;
  final Color dateHeaderBackground;
  final Color dateHeaderBorder;
  final Color dateHeaderTextColor;
  final Color rowBackground;
  final Color rowBorder;
  final Color accentColor;
  final IconData leadingIcon;
  final bool allowDelete;
  final ScrollController? controller;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final sections = <String, List<T>>{};
    final orderedDates = <String>[];
    for (final item in records) {
      final localDate = measuredAtOf(item).toLocal();
      final dateKey = DateFormat('yyyy-MM-dd').format(localDate);
      if (!sections.containsKey(dateKey)) {
        sections[dateKey] = <T>[];
        orderedDates.add(dateKey);
      }
      sections[dateKey]!.add(item);
    }
    orderedDates.sort((a, b) => b.compareTo(a));
    for (final entry in sections.entries) {
      entry.value.sort(
        (a, b) =>
            measuredAtOf(b).toLocal().compareTo(measuredAtOf(a).toLocal()),
      );
    }

    final screenH = MediaQuery.sizeOf(context).height;
    final listHeight = math.min(460.0, math.max(220.0, screenH * 0.50));

    final theme = Theme.of(context);
    return SizedBox(
      height: listHeight,
      child: ListView.builder(
        controller: controller,
        itemCount: orderedDates.length + (footer == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (index == orderedDates.length) {
            return footer!;
          }
          final dateKey = orderedDates[index];
          final sectionItems = sections[dateKey]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: dateHeaderBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: dateHeaderBorder, width: 1),
                  ),
                  child: Text(
                    dateKey,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: dateHeaderTextColor,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...sectionItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Slidable(
                        key: ValueKey('history-${itemIdOf(item)}'),
                        closeOnScroll: true,
                        endActionPane: allowDelete
                            ? ActionPane(
                                // BehindMotion keeps row shape stable and reveals action inside the row bounds.
                                motion: const BehindMotion(),
                                extentRatio: 1 / 3,
                                children: [
                                  CustomSlidableAction(
                                    onPressed: (_) async {
                                      final deleted = await onDelete(item);
                                      if (!deleted && context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              AppLocalizations.of(
                                                context,
                                              )!.deleteFailedMessage,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    backgroundColor: theme.colorScheme.error,
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Center(
                                      child: Icon(
                                        Icons.delete,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : null,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: rowBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: rowBorder, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 9,
                              horizontal: 12,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(leadingIcon, color: accentColor, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    rowTextBuilder(item),
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: rowTextColorBuilder(item),
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
