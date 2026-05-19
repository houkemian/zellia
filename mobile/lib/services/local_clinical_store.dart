import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'api_service.dart';
import 'local_database_service.dart';

const _uuid = Uuid();
const _maxSyncRetries = 20;
const _syncedRetentionDays = 7;

/// Local-first writes for vitals and medication check-ins.
class LocalClinicalStore {
  LocalClinicalStore._();
  static final LocalClinicalStore instance = LocalClinicalStore._();

  Future<Database> get _db => LocalDatabaseService.instance.database;

  String newIdempotencyKey() => _uuid.v4();

  Future<PendingBloodPressureRow> saveBloodPressureLocal({
    required int systolic,
    required int diastolic,
    int? heartRate,
    required DateTime measuredAt,
  }) async {
    final now = DateTime.now();
    final key = newIdempotencyKey();
    final row = PendingBloodPressureRow(
      localId: 0,
      idempotencyKey: key,
      systolic: systolic,
      diastolic: diastolic,
      heartRate: heartRate,
      measuredAtLocal: measuredAt,
      createdAtLocal: now,
      isSynced: false,
      syncRetryCount: 0,
    );
    final id = await (await _db).insert(
      'pending_blood_pressure',
      row.toMap()..remove('local_id'),
    );
    return row.copyWith(localId: id);
  }

  Future<PendingBloodSugarRow> saveBloodSugarLocal({
    required double level,
    required String condition,
    required DateTime measuredAt,
  }) async {
    final now = DateTime.now();
    final key = newIdempotencyKey();
    final row = PendingBloodSugarRow(
      localId: 0,
      idempotencyKey: key,
      level: level,
      conditionCode: condition,
      measuredAtLocal: measuredAt,
      createdAtLocal: now,
      isSynced: false,
      syncRetryCount: 0,
    );
    final id = await (await _db).insert(
      'pending_blood_sugar',
      row.toMap()..remove('local_id'),
    );
    return row.copyWith(localId: id);
  }

  Future<PendingMedicationLogRow> saveMedicationLogLocal({
    required int planId,
    required DateTime takenDate,
    required String scheduledTime,
    required bool isTaken,
  }) async {
    final now = DateTime.now();
    final takenDateOnly = DateTime(
      takenDate.year,
      takenDate.month,
      takenDate.day,
    );
    final key = newIdempotencyKey();
    final row = PendingMedicationLogRow(
      localId: 0,
      idempotencyKey: key,
      planId: planId,
      takenDate: takenDateOnly,
      scheduledTime: scheduledTime,
      isTaken: isTaken,
      createdAtLocal: now,
      isSynced: false,
      syncRetryCount: 0,
    );
    final id = await (await _db).insert(
      'pending_medication_logs',
      row.toMap()..remove('local_id'),
    );
    return row.copyWith(localId: id);
  }

  Future<List<PendingBloodPressureRow>> listUnsyncedBloodPressure() async {
    final rows = await (await _db).query(
      'pending_blood_pressure',
      where: 'is_synced = ? AND sync_retry_count < ?',
      whereArgs: [0, _maxSyncRetries],
      orderBy: 'created_at_local ASC',
    );
    return rows.map(PendingBloodPressureRow.fromMap).toList();
  }

  Future<List<PendingBloodSugarRow>> listUnsyncedBloodSugar() async {
    final rows = await (await _db).query(
      'pending_blood_sugar',
      where: 'is_synced = ? AND sync_retry_count < ?',
      whereArgs: [0, _maxSyncRetries],
      orderBy: 'created_at_local ASC',
    );
    return rows.map(PendingBloodSugarRow.fromMap).toList();
  }

  Future<List<PendingMedicationLogRow>> listUnsyncedMedicationLogs() async {
    final rows = await (await _db).query(
      'pending_medication_logs',
      where: 'is_synced = ? AND sync_retry_count < ?',
      whereArgs: [0, _maxSyncRetries],
      orderBy: 'created_at_local ASC',
    );
    return rows.map(PendingMedicationLogRow.fromMap).toList();
  }

  Future<void> markBloodPressureSynced(int localId, {int? serverId}) async {
    await (await _db).update(
      'pending_blood_pressure',
      {'is_synced': 1, if (serverId != null) 'server_id': serverId},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markBloodSugarSynced(int localId, {int? serverId}) async {
    await (await _db).update(
      'pending_blood_sugar',
      {'is_synced': 1, if (serverId != null) 'server_id': serverId},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markMedicationLogSynced(int localId, {int? serverLogId}) async {
    await (await _db).update(
      'pending_medication_logs',
      {
        'is_synced': 1,
        if (serverLogId != null) 'server_log_id': serverLogId,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> incrementRetry(String table, int localId) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await (await _db).rawUpdate(
      '''
      UPDATE $table
      SET sync_retry_count = sync_retry_count + 1,
          last_sync_attempt_at = ?
      WHERE local_id = ?
      ''',
      [nowIso, localId],
    );
  }

  Future<void> purgeStaleRecords() async {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: _syncedRetentionDays))
        .toUtc()
        .toIso8601String();
    final db = await _db;
    for (final table in [
      'pending_blood_pressure',
      'pending_blood_sugar',
      'pending_medication_logs',
    ]) {
      await db.delete(
        table,
        where: 'is_synced = 1 AND created_at_local < ?',
        whereArgs: [cutoff],
      );
      await db.delete(
        table,
        where: 'sync_retry_count >= ?',
        whereArgs: [_maxSyncRetries],
      );
    }
  }

  Future<PendingBloodPressureRow?> latestLocalBloodPressureForToday() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final rows = await (await _db).query(
      'pending_blood_pressure',
      where: 'substr(measured_at_local, 1, 10) = ?',
      whereArgs: [today],
      orderBy: 'created_at_local DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PendingBloodPressureRow.fromMap(rows.first);
  }

  Future<PendingBloodSugarRow?> latestLocalBloodSugarForToday() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final rows = await (await _db).query(
      'pending_blood_sugar',
      where: "substr(measured_at_local, 1, 10) = ?",
      whereArgs: [today],
      orderBy: 'created_at_local DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PendingBloodSugarRow.fromMap(rows.first);
  }

  Future<List<PendingMedicationLogRow>> pendingMedicationOverridesForToday(
    DateTime takenDate,
  ) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(takenDate);
    final rows = await (await _db).query(
      'pending_medication_logs',
      where: 'taken_date = ? AND is_synced = 0',
      whereArgs: [dateKey],
      orderBy: 'created_at_local ASC',
    );
    return rows.map(PendingMedicationLogRow.fromMap).toList();
  }

  List<TodayMedicationItemDto> mergeTodayMedications(
    List<TodayMedicationItemDto> serverItems,
    List<PendingMedicationLogRow> pending,
  ) {
    if (pending.isEmpty) return serverItems;
    final overrideBySlot = <String, PendingMedicationLogRow>{};
    for (final row in pending) {
      final key = '${row.planId}|${row.scheduledTime}';
      overrideBySlot[key] = row;
    }
    return serverItems.map((item) {
      final key = '${item.planId}|${item.scheduledTime}';
      final local = overrideBySlot[key];
      if (local == null) return item;
      return TodayMedicationItemDto(
        planId: item.planId,
        name: item.name,
        dosage: item.dosage,
        scheduledTime: item.scheduledTime,
        takenDate: item.takenDate,
        logId: item.logId,
        isTaken: local.isTaken,
        checkedAt: local.isTaken ? local.createdAtLocal : null,
        notifyMissed: item.notifyMissed,
        notifyDelayMinutes: item.notifyDelayMinutes,
        voiceUrl: item.voiceUrl,
        familyVoiceCaregiverId: item.familyVoiceCaregiverId,
      );
    }).toList();
  }

  BloodPressureRecordDto toBloodPressureDto(
    PendingBloodPressureRow row, {
    int userId = 0,
  }) {
    return BloodPressureRecordDto(
      id: row.serverId ?? -row.localId,
      userId: userId,
      systolic: row.systolic,
      diastolic: row.diastolic,
      heartRate: row.heartRate,
      measuredAt: row.measuredAtLocal,
    );
  }

  BloodSugarRecordDto toBloodSugarDto(
    PendingBloodSugarRow row, {
    int userId = 0,
  }) {
    return BloodSugarRecordDto(
      id: row.serverId ?? -row.localId,
      userId: userId,
      level: row.level,
      condition: row.conditionCode,
      measuredAt: row.measuredAtLocal,
    );
  }
}

class PendingBloodPressureRow {
  PendingBloodPressureRow({
    required this.localId,
    required this.idempotencyKey,
    required this.systolic,
    required this.diastolic,
    this.heartRate,
    required this.measuredAtLocal,
    required this.createdAtLocal,
    required this.isSynced,
    required this.syncRetryCount,
    this.serverId,
    this.lastSyncAttemptAt,
  });

  final int localId;
  final String idempotencyKey;
  final int systolic;
  final int diastolic;
  final int? heartRate;
  final DateTime measuredAtLocal;
  final DateTime createdAtLocal;
  final bool isSynced;
  final int syncRetryCount;
  final int? serverId;
  final DateTime? lastSyncAttemptAt;

  PendingBloodPressureRow copyWith({int? localId}) {
    return PendingBloodPressureRow(
      localId: localId ?? this.localId,
      idempotencyKey: idempotencyKey,
      systolic: systolic,
      diastolic: diastolic,
      heartRate: heartRate,
      measuredAtLocal: measuredAtLocal,
      createdAtLocal: createdAtLocal,
      isSynced: isSynced,
      syncRetryCount: syncRetryCount,
      serverId: serverId,
      lastSyncAttemptAt: lastSyncAttemptAt,
    );
  }

  Map<String, Object?> toMap() => {
        'local_id': localId,
        'idempotency_key': idempotencyKey,
        'systolic': systolic,
        'diastolic': diastolic,
        'heart_rate': heartRate,
        'measured_at_local': measuredAtLocal.toUtc().toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'created_at_local': createdAtLocal.toUtc().toIso8601String(),
        'sync_retry_count': syncRetryCount,
        'server_id': serverId,
        'last_sync_attempt_at': lastSyncAttemptAt?.toUtc().toIso8601String(),
      };

  static PendingBloodPressureRow fromMap(Map<String, Object?> map) {
    return PendingBloodPressureRow(
      localId: map['local_id'] as int,
      idempotencyKey: map['idempotency_key'] as String,
      systolic: map['systolic'] as int,
      diastolic: map['diastolic'] as int,
      heartRate: map['heart_rate'] as int?,
      measuredAtLocal: DateTime.parse(map['measured_at_local'] as String).toLocal(),
      createdAtLocal: DateTime.parse(map['created_at_local'] as String).toLocal(),
      isSynced: (map['is_synced'] as int) == 1,
      syncRetryCount: map['sync_retry_count'] as int? ?? 0,
      serverId: map['server_id'] as int?,
      lastSyncAttemptAt: map['last_sync_attempt_at'] != null
          ? DateTime.parse(map['last_sync_attempt_at'] as String).toLocal()
          : null,
    );
  }
}

class PendingBloodSugarRow {
  PendingBloodSugarRow({
    required this.localId,
    required this.idempotencyKey,
    required this.level,
    required this.conditionCode,
    required this.measuredAtLocal,
    required this.createdAtLocal,
    required this.isSynced,
    required this.syncRetryCount,
    this.serverId,
    this.lastSyncAttemptAt,
  });

  final int localId;
  final String idempotencyKey;
  final double level;
  final String conditionCode;
  final DateTime measuredAtLocal;
  final DateTime createdAtLocal;
  final bool isSynced;
  final int syncRetryCount;
  final int? serverId;
  final DateTime? lastSyncAttemptAt;

  PendingBloodSugarRow copyWith({int? localId}) {
    return PendingBloodSugarRow(
      localId: localId ?? this.localId,
      idempotencyKey: idempotencyKey,
      level: level,
      conditionCode: conditionCode,
      measuredAtLocal: measuredAtLocal,
      createdAtLocal: createdAtLocal,
      isSynced: isSynced,
      syncRetryCount: syncRetryCount,
      serverId: serverId,
      lastSyncAttemptAt: lastSyncAttemptAt,
    );
  }

  Map<String, Object?> toMap() => {
        'local_id': localId,
        'idempotency_key': idempotencyKey,
        'level': level,
        'condition_code': conditionCode,
        'measured_at_local': measuredAtLocal.toUtc().toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'created_at_local': createdAtLocal.toUtc().toIso8601String(),
        'sync_retry_count': syncRetryCount,
        'server_id': serverId,
        'last_sync_attempt_at': lastSyncAttemptAt?.toUtc().toIso8601String(),
      };

  static PendingBloodSugarRow fromMap(Map<String, Object?> map) {
    return PendingBloodSugarRow(
      localId: map['local_id'] as int,
      idempotencyKey: map['idempotency_key'] as String,
      level: (map['level'] as num).toDouble(),
      conditionCode: map['condition_code'] as String,
      measuredAtLocal: DateTime.parse(map['measured_at_local'] as String).toLocal(),
      createdAtLocal: DateTime.parse(map['created_at_local'] as String).toLocal(),
      isSynced: (map['is_synced'] as int) == 1,
      syncRetryCount: map['sync_retry_count'] as int? ?? 0,
      serverId: map['server_id'] as int?,
      lastSyncAttemptAt: map['last_sync_attempt_at'] != null
          ? DateTime.parse(map['last_sync_attempt_at'] as String).toLocal()
          : null,
    );
  }
}

class PendingMedicationLogRow {
  PendingMedicationLogRow({
    required this.localId,
    required this.idempotencyKey,
    required this.planId,
    required this.takenDate,
    required this.scheduledTime,
    required this.isTaken,
    required this.createdAtLocal,
    required this.isSynced,
    required this.syncRetryCount,
    this.serverLogId,
    this.lastSyncAttemptAt,
  });

  final int localId;
  final String idempotencyKey;
  final int planId;
  final DateTime takenDate;
  final String scheduledTime;
  final bool isTaken;
  final DateTime createdAtLocal;
  final bool isSynced;
  final int syncRetryCount;
  final int? serverLogId;
  final DateTime? lastSyncAttemptAt;

  PendingMedicationLogRow copyWith({int? localId}) {
    return PendingMedicationLogRow(
      localId: localId ?? this.localId,
      idempotencyKey: idempotencyKey,
      planId: planId,
      takenDate: takenDate,
      scheduledTime: scheduledTime,
      isTaken: isTaken,
      createdAtLocal: createdAtLocal,
      isSynced: isSynced,
      syncRetryCount: syncRetryCount,
      serverLogId: serverLogId,
      lastSyncAttemptAt: lastSyncAttemptAt,
    );
  }

  Map<String, Object?> toMap() => {
        'local_id': localId,
        'idempotency_key': idempotencyKey,
        'plan_id': planId,
        'taken_date': DateFormat('yyyy-MM-dd').format(takenDate),
        'scheduled_time': scheduledTime,
        'is_taken': isTaken ? 1 : 0,
        'is_synced': isSynced ? 1 : 0,
        'created_at_local': createdAtLocal.toUtc().toIso8601String(),
        'sync_retry_count': syncRetryCount,
        'server_log_id': serverLogId,
        'last_sync_attempt_at': lastSyncAttemptAt?.toUtc().toIso8601String(),
      };

  static PendingMedicationLogRow fromMap(Map<String, Object?> map) {
    return PendingMedicationLogRow(
      localId: map['local_id'] as int,
      idempotencyKey: map['idempotency_key'] as String,
      planId: map['plan_id'] as int,
      takenDate: DateTime.parse(map['taken_date'] as String),
      scheduledTime: map['scheduled_time'] as String,
      isTaken: (map['is_taken'] as int) == 1,
      createdAtLocal: DateTime.parse(map['created_at_local'] as String).toLocal(),
      isSynced: (map['is_synced'] as int) == 1,
      syncRetryCount: map['sync_retry_count'] as int? ?? 0,
      serverLogId: map['server_log_id'] as int?,
      lastSyncAttemptAt: map['last_sync_attempt_at'] != null
          ? DateTime.parse(map['last_sync_attempt_at'] as String).toLocal()
          : null,
    );
  }
}
