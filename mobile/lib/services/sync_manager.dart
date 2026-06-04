import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'local_clinical_store.dart';

/// Background sync of offline vitals and medication logs (silent, no UI toasts).
class SyncManager {
  SyncManager._();
  static final SyncManager instance = SyncManager._();

  static const _baseBackoffSeconds = 2;
  static const _maxBackoffSeconds = 300;

  ApiService? _api;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncInProgress = false;

  void attach(ApiService api) {
    _api = api;
  }

  Future<void> initialize(ApiService api) async {
    attach(api);
    try {
      await _connectivitySub?.cancel();
      _connectivitySub = Connectivity().onConnectivityChanged.listen(
        _onConnectivityChanged,
        onError: (Object e, StackTrace st) {
          if (kDebugMode) {
            debugPrint('[SyncManager] connectivity listener error: $e\n$st');
          }
        },
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SyncManager] init connectivity failed: $e\n$st');
      }
    }
    unawaited(syncPending());
  }

  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _api = null;
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_hasNetwork(results)) {
      unawaited(syncPending());
    }
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn,
    );
  }

  Future<bool> isDeviceOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return _hasNetwork(results);
    } catch (_) {
      return false;
    }
  }

  Duration _backoffDelay(int retryCount) {
    final seconds = math.min(
      _maxBackoffSeconds,
      _baseBackoffSeconds * math.pow(2, retryCount).toInt(),
    );
    return Duration(seconds: seconds);
  }

  bool _shouldAttemptSync({required int retryCount, DateTime? lastAttempt}) {
    if (retryCount <= 0) return true;
    if (lastAttempt == null) return true;
    final elapsed = DateTime.now().difference(lastAttempt);
    return elapsed >= _backoffDelay(retryCount);
  }

  Future<void> syncPending() async {
    if (_syncInProgress) return;
    final api = _api;
    if (api == null) return;
    if (!await isDeviceOnline()) return;

    _syncInProgress = true;
    try {
      await _syncBloodPressure(api);
      await _syncBloodSugar(api);
      await _syncMedicationLogs(api);
      await LocalClinicalStore.instance.purgeStaleRecords();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SyncManager] syncPending failed: $e\n$st');
      }
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> _syncBloodPressure(ApiService api) async {
    final store = LocalClinicalStore.instance;
    final pending = await store.listUnsyncedBloodPressure();
    for (final row in pending) {
      if (!_shouldAttemptSync(
        retryCount: row.syncRetryCount,
        lastAttempt: row.lastSyncAttemptAt,
      )) {
        continue;
      }
      try {
        final dto = await api.syncBloodPressure(
          systolic: row.systolic,
          diastolic: row.diastolic,
          heartRate: row.heartRate,
          measuredAt: row.measuredAtLocal,
          idempotencyKey: row.idempotencyKey,
          createdAtLocal: row.createdAtLocal,
        );
        await store.markBloodPressureSynced(row.localId, serverId: dto.id);
        ApiService.onPostTargetUserClinicalRefresh?.call(
          api,
          currentViewUserId,
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[SyncManager] BP sync failed ${row.idempotencyKey}: $e');
        }
        if (e is ApiException && e.isPermanentClientError) {
          await store.markBloodPressureSynced(row.localId);
        } else {
          await store.incrementRetry('pending_blood_pressure', row.localId);
        }
        if (kDebugMode) debugPrint(st.toString());
      }
    }
  }

  Future<void> _syncBloodSugar(ApiService api) async {
    final store = LocalClinicalStore.instance;
    final pending = await store.listUnsyncedBloodSugar();
    for (final row in pending) {
      if (!_shouldAttemptSync(
        retryCount: row.syncRetryCount,
        lastAttempt: row.lastSyncAttemptAt,
      )) {
        continue;
      }
      try {
        final dto = await api.syncBloodSugar(
          level: row.level,
          condition: row.conditionCode,
          measuredAt: row.measuredAtLocal,
          idempotencyKey: row.idempotencyKey,
          createdAtLocal: row.createdAtLocal,
        );
        await store.markBloodSugarSynced(row.localId, serverId: dto.id);
        ApiService.onPostTargetUserClinicalRefresh?.call(
          api,
          currentViewUserId,
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[SyncManager] BS sync failed ${row.idempotencyKey}: $e');
        }
        if (e is ApiException && e.isPermanentClientError) {
          await store.markBloodSugarSynced(row.localId);
        } else {
          await store.incrementRetry('pending_blood_sugar', row.localId);
        }
        if (kDebugMode) debugPrint(st.toString());
      }
    }
  }

  Future<void> _syncMedicationLogs(ApiService api) async {
    final store = LocalClinicalStore.instance;
    final pending = await store.listUnsyncedMedicationLogs();
    for (final row in pending) {
      if (!_shouldAttemptSync(
        retryCount: row.syncRetryCount,
        lastAttempt: row.lastSyncAttemptAt,
      )) {
        continue;
      }
      try {
        final hhmm = row.scheduledTime.split(':');
        final hour = int.parse(hhmm.first);
        final minute = int.parse(hhmm.last);
        final result = await api.syncMedicationLog(
          planId: row.planId,
          takenDate: row.takenDate,
          scheduledTime:
              '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00',
          isTaken: row.isTaken,
          idempotencyKey: row.idempotencyKey,
          createdAtLocal: row.createdAtLocal,
        );
        final serverId = result['id'] as int?;
        await store.markMedicationLogSynced(row.localId, serverLogId: serverId);
        ApiService.onPostTargetUserClinicalRefresh?.call(
          api,
          currentViewUserId,
        );
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[SyncManager] med sync failed ${row.idempotencyKey}: $e');
        }
        if (e is ApiException && e.isPermanentClientError) {
          await store.markMedicationLogSynced(row.localId);
        } else {
          await store.incrementRetry('pending_medication_logs', row.localId);
        }
        if (kDebugMode) debugPrint(st.toString());
      }
    }
  }

  /// Called when app returns to foreground.
  void onAppResumed() {
    unawaited(syncPending());
  }
}
