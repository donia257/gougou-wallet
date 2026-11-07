import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'ledger.dart';

class RecoverySnapshot {
  const RecoverySnapshot({
    required this.id,
    required this.createdAt,
    required this.reason,
    required this.ledger,
  });
  final int id;
  final DateTime createdAt;
  final String reason;
  final Ledger ledger;
}

class LedgerRepository {
  LedgerRepository({DatabaseFactory? factory, String? databasePath})
    : _providedFactory = factory,
      _path = databasePath;
  final DatabaseFactory? _providedFactory;
  DatabaseFactory get _factory => _providedFactory ?? databaseFactory;
  final String? _path;
  Database? _database;

  Future<void> _openDatabase() async {
    _database ??= await _factory.openDatabase(
      _path ?? path.join(await getDatabasesPath(), 'daily_ledger.db'),
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE ledger (id INTEGER PRIMARY KEY CHECK(id = 1), data TEXT NOT NULL)',
          );
          await _createSnapshots(db);
        },
        onUpgrade: (db, oldVersion, newVersion) => _createSnapshots(db),
      ),
    );
  }

  static Future<void> _createSnapshots(DatabaseExecutor db) => db.execute(
    'CREATE TABLE IF NOT EXISTS snapshots (id INTEGER PRIMARY KEY AUTOINCREMENT, createdAt TEXT NOT NULL, reason TEXT NOT NULL, data TEXT NOT NULL)',
  );

  Future<Ledger> open() async {
    await _openDatabase();
    final rows = await _database!.query(
      'ledger',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (rows.isEmpty) return Ledger.empty();
    final raw = rows.single['data'] as String;
    final ledger = Ledger.decode(raw);
    if ((jsonDecode(raw) as Map)['version'] == 1) {
      await _database!.transaction((transaction) async {
        await _snapshot(transaction, raw, '升级到 v0.2.0 之前');
        await _write(transaction, ledger);
      });
    }
    return ledger;
  }

  Future<void> save(Ledger ledger, {String? snapshotReason}) async {
    ledger.validate();
    await _openDatabase();
    await _database!.transaction((transaction) async {
      final rows = await transaction.query(
        'ledger',
        where: 'id = ?',
        whereArgs: [1],
      );
      if (rows.isNotEmpty) {
        final raw = rows.single['data'] as String;
        var valid = true;
        try {
          Ledger.decode(raw);
        } catch (_) {
          valid = false;
        }
        if (valid) {
          final today = '${dayKey(DateTime.now())}%';
          final snapshots = await transaction.query(
            'snapshots',
            columns: ['id'],
            where: 'createdAt LIKE ?',
            whereArgs: [today],
            limit: 1,
          );
          if (snapshotReason != null || snapshots.isEmpty) {
            await _snapshot(transaction, raw, snapshotReason ?? '每日首次修改之前');
          }
        }
      }
      await _write(transaction, ledger);
    });
  }

  Future<void> _write(DatabaseExecutor db, Ledger ledger) async {
    await db.insert('ledger', {
      'id': 1,
      'data': ledger.encode(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _snapshot(DatabaseExecutor db, String raw, String reason) async {
    Ledger.decode(raw);
    await db.insert('snapshots', {
      'createdAt': DateTime.now().toIso8601String(),
      'reason': reason,
      'data': raw,
    });
    await db.execute(
      'DELETE FROM snapshots WHERE id NOT IN (SELECT id FROM snapshots ORDER BY id DESC LIMIT 5)',
    );
  }

  Future<List<RecoverySnapshot>> snapshots() async {
    await _openDatabase();
    final rows = await _database!.query('snapshots', orderBy: 'id DESC');
    final result = <RecoverySnapshot>[];
    for (final row in rows) {
      try {
        result.add(
          RecoverySnapshot(
            id: row['id'] as int,
            createdAt: DateTime.parse(row['createdAt'] as String),
            reason: row['reason'] as String,
            ledger: Ledger.decode(row['data'] as String),
          ),
        );
      } catch (_) {
        /* A damaged snapshot cannot be used as a recovery point. */
      }
    }
    return result;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
