import 'dart:convert';
import 'dart:io';
import 'package:daily_ledger/ledger.dart';
import 'package:daily_ledger/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final legacy = File('test/fixtures/v0.1.0.json').readAsStringSync();
  late Directory directory;
  late String databasePath;
  late LedgerRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gougou-migration-');
    databasePath = path.join(directory.path, 'daily_ledger.db');
    final old = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE ledger (id INTEGER PRIMARY KEY CHECK(id = 1), data TEXT NOT NULL)',
          );
          await db.insert('ledger', {'id': 1, 'data': legacy});
        },
      ),
    );
    await old.close();
    repository = LedgerRepository(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  test(
    'upgrade an actual v1 SQLite database and preserve balances, times, budgets and entries',
    () async {
      final ledger = await repository.open();
      expect(ledger.entries.length, 4);
      expect(ledger.balance('cash'), 289995);
      expect(ledger.balance('wechat'), 16889);
      expect(ledger.total(EntryType.expense, DateTime(2026, 11)), 12250);
      expect(ledger.budgets['2026-11'], 120000);
      expect(ledger.categoryName(ledger.entries.last), '狗粮');
      expect(ledger.entries[1].date.hour, 12);
      expect(ledger.entries[1].date.minute, 28);
      final snapshots = await repository.snapshots();
      expect(snapshots.length, 1);
      expect(snapshots.single.ledger.encode(), ledger.encode());
      await repository.close();
      expect((await repository.open()).encode(), ledger.encode());
      expect((await repository.snapshots()).length, 1);
    },
  );

  test(
    'rename and merge categories after migration without losing history',
    () async {
      final original = await repository.open();
      final renamed = original.copyWith(
        categories: original.categories
            .map((c) => c.id == 'expense-1' ? c.copyWith(name: '宠物') : c)
            .toList(),
      );
      await repository.save(renamed);
      final merged = renamed.removeCategory(
        'expense-1',
        replacementId: 'expense-0',
      );
      await repository.save(merged);
      final restored = await repository.open();
      expect(restored.entries.length, 4);
      expect(restored.categoryName(restored.entries.last), '餐饮');
      expect(restored.balance('cash'), original.balance('cash'));
      expect(restored.balance('wechat'), original.balance('wechat'));
      expect(
        () => original.removeCategory('expense-1', replacementId: 'income-0'),
        throwsFormatException,
      );
    },
  );

  test(
    'retain five validated recovery points and restore old backup after edits',
    () async {
      var ledger = await repository.open();
      for (var i = 0; i < 7; i++) {
        ledger = ledger.copyWith(budgets: {'2026-11': 10000 + i});
        await repository.save(ledger, snapshotReason: 'test recovery $i');
      }
      final snapshots = await repository.snapshots();
      expect(snapshots.length, 5);
      expect(snapshots.first.ledger.budgets['2026-11'], 10005);
      await repository.save(Ledger.decode(legacy), snapshotReason: '恢复外部备份之前');
      expect((await repository.open()).budgets['2026-11'], 120000);
      expect(
        (await repository.snapshots()).first.ledger.budgets['2026-11'],
        10006,
      );
    },
  );

  test('a rejected save leaves persisted data and snapshots usable', () async {
    final ledger = await repository.open();
    await expectLater(
      repository.save(ledger.copyWith(budgets: {'invalid': -1})),
      throwsFormatException,
    );
    expect((await repository.open()).encode(), ledger.encode());
    expect((await repository.snapshots()).length, 1);
  });

  test(
    'transaction rollback preserves ledger if the snapshot cannot be written',
    () async {
      final ledger = await repository.open();
      final db = await databaseFactoryFfi.openDatabase(databasePath);
      await db.execute(
        "CREATE TRIGGER fail_snapshot BEFORE INSERT ON snapshots BEGIN SELECT RAISE(ABORT, 'simulated disk write error'); END",
      );
      await expectLater(
        repository.save(
          ledger.copyWith(budgets: {'2026-11': 22222}),
          snapshotReason: 'fail',
        ),
        throwsA(anything),
      );
      expect((await repository.open()).encode(), ledger.encode());
    },
  );

  test(
    'corrupted current JSON can be recovered from an existing snapshot',
    () async {
      final ledger = await repository.open();
      final db = await databaseFactoryFfi.openDatabase(databasePath);
      await db.update('ledger', {'data': '{damaged'}, where: 'id = 1');
      await expectLater(repository.open(), throwsFormatException);
      final snapshot = (await repository.snapshots()).first;
      await repository.save(snapshot.ledger, snapshotReason: 'recovery');
      expect((await repository.open()).encode(), ledger.encode());
    },
  );

  test('date range includes the end day and transfer destination account', () {
    final ledger = Ledger.decode(legacy);
    expect(
      ledger
          .selectEntries(
            start: DateTime(2026, 11, 7),
            end: DateTime(2026, 11, 7),
          )
          .length,
      2,
    );
    expect(
      ledger
          .selectEntries(
            start: DateTime(2026, 11, 6),
            end: DateTime(2026, 11, 7),
            accountId: 'wechat',
          )
          .length,
      2,
    );
    expect(
      ledger
          .selectEntries(
            start: DateTime(2026, 11, 6),
            end: DateTime(2026, 11, 7),
            type: EntryType.expense,
            categoryId: 'expense-1',
            query: '自定义',
          )
          .single
          .id,
      'legacy-pet',
    );
    final invalidDate = jsonDecode(legacy) as Map<String, dynamic>;
    (invalidDate['entries'] as List).first['date'] = '2026-02-31T12:00:00.000';
    expect(() => Ledger.decode(jsonEncode(invalidDate)), throwsFormatException);
  });

  test('legacy UTC timestamps retain the date and time shown by v0.1.0', () {
    final data = jsonDecode(legacy) as Map<String, dynamic>;
    (data['entries'] as List).first['date'] = '2026-11-06T00:30:00.000Z';
    final ledger = Ledger.decode(jsonEncode(data));
    expect(ledger.entries.first.date.hour, 0);
    expect(ledger.entries.first.date.minute, 30);
    expect(ledger.entries.first.date.isUtc, isTrue);
    expect(
      ledger
          .selectEntries(
            start: DateTime(2026, 11, 6),
            end: DateTime(2026, 11, 6),
            type: EntryType.income,
          )
          .single
          .id,
      'legacy-income',
    );
  });
}
