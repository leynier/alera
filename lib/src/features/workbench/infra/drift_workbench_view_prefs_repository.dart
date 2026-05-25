import 'dart:convert';

import 'package:alera/src/features/workbench/application/workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;

class DriftWorkbenchViewPrefsRepository
    implements WorkbenchViewPrefsRepository {
  DriftWorkbenchViewPrefsRepository(this._db);

  final AleraDatabase _db;

  static const int _rowId = 1;

  @override
  Future<WorkbenchViewPrefs> load() async {
    final row = await (_db.select(_db.workbenchViewPrefsTable)
          ..where((table) => table.id.equals(_rowId)))
        .getSingleOrNull();
    if (row == null) {
      return WorkbenchViewPrefs.defaults;
    }
    try {
      final decoded = jsonDecode(row.dataJson);
      if (decoded is! Map) {
        return WorkbenchViewPrefs.defaults;
      }
      return WorkbenchViewPrefs.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return WorkbenchViewPrefs.defaults;
    }
  }

  @override
  Future<void> save(WorkbenchViewPrefs prefs) async {
    await _db.into(_db.workbenchViewPrefsTable).insertOnConflictUpdate(
      WorkbenchViewPrefsTableCompanion(
        id: const Value(_rowId),
        dataJson: Value(jsonEncode(prefs.toMap())),
      ),
    );
  }
}
