import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite tables for offline-first vitals and medication check-ins.
class LocalDatabaseService {
  LocalDatabaseService._();
  static final LocalDatabaseService instance = LocalDatabaseService._();

  static const _dbName = 'zellia_offline.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE pending_blood_pressure (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        idempotency_key TEXT NOT NULL UNIQUE,
        systolic INTEGER NOT NULL,
        diastolic INTEGER NOT NULL,
        heart_rate INTEGER,
        measured_at_local TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        created_at_local TEXT NOT NULL,
        sync_retry_count INTEGER NOT NULL DEFAULT 0,
        server_id INTEGER,
        last_sync_attempt_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_blood_sugar (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        idempotency_key TEXT NOT NULL UNIQUE,
        level REAL NOT NULL,
        condition_code TEXT NOT NULL,
        measured_at_local TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        created_at_local TEXT NOT NULL,
        sync_retry_count INTEGER NOT NULL DEFAULT 0,
        server_id INTEGER,
        last_sync_attempt_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_medication_logs (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        idempotency_key TEXT NOT NULL UNIQUE,
        plan_id INTEGER NOT NULL,
        taken_date TEXT NOT NULL,
        scheduled_time TEXT NOT NULL,
        is_taken INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        created_at_local TEXT NOT NULL,
        sync_retry_count INTEGER NOT NULL DEFAULT 0,
        server_log_id INTEGER,
        last_sync_attempt_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_pending_bp_unsynced ON pending_blood_pressure (is_synced, created_at_local)',
    );
    await db.execute(
      'CREATE INDEX idx_pending_bs_unsynced ON pending_blood_sugar (is_synced, created_at_local)',
    );
    await db.execute(
      'CREATE INDEX idx_pending_med_unsynced ON pending_medication_logs (is_synced, created_at_local)',
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
