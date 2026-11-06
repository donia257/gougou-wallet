import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'ledger.dart';

/// Each commit replaces one complete snapshot inside a SQLite transaction.
/// Balances are derived from entries, so transfers and deletion stay consistent.
class LedgerRepository {
  Database? _database;

  Future<Ledger> open() async {
    final database = await openDatabase(
      path.join(await getDatabasesPath(), 'daily_ledger.db'),
      version: 1,
      onCreate: (db, version) => db.execute(
        'CREATE TABLE ledger (id INTEGER PRIMARY KEY CHECK(id = 1), data TEXT NOT NULL)',
      ),
    );
    _database = database;
    final rows = await database.query(
      'ledger',
      where: 'id = ?',
      whereArgs: [1],
    );
    return rows.isEmpty
        ? Ledger.empty()
        : Ledger.decode(rows.single['data'] as String);
  }

  Future<void> save(Ledger ledger) async {
    ledger.validate();
    final data = ledger.encode();
    await _database!.transaction((transaction) async {
      await transaction.insert('ledger', {
        'id': 1,
        'data': data,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
