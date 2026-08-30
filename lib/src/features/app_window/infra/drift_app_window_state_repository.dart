import 'dart:convert';

import 'package:alera/src/features/app_window/application/app_window_state_repository.dart';
import 'package:alera/src/features/app_window/domain/app_window_state.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;

class DriftAppWindowStateRepository(final AleraDatabase _db)
    implements AppWindowStateRepository {
  static const int _rowId = 1;

  @override
  Future<AppWindowState?> load() async {
    final row = await (_db.select(
      _db.appWindowStateTable,
    )..where((table) => table.id.equals(_rowId))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(row.dataJson);
      return AppWindowState.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(AppWindowState state) async {
    await _db
        .into(_db.appWindowStateTable)
        .insertOnConflictUpdate(
          AppWindowStateTableCompanion(
            id: const Value(_rowId),
            dataJson: Value(jsonEncode(state.toJson())),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  @override
  Future<void> clear() async {
    await (_db.delete(
      _db.appWindowStateTable,
    )..where((table) => table.id.equals(_rowId))).go();
  }
}
