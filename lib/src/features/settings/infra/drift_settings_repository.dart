import 'dart:convert';

import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AleraDatabase _db;

  static const int _rowId = 1;

  @override
  Future<AleraSettings> load() async {
    final row = await (_db.select(
      _db.appSettingsTable,
    )..where((table) => table.id.equals(_rowId))).getSingleOrNull();
    if (row == null) {
      return AleraSettings.defaults;
    }
    try {
      final decoded = jsonDecode(row.dataJson);
      if (decoded is! Map) {
        return AleraSettings.defaults;
      }
      return AleraSettings.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return AleraSettings.defaults;
    }
  }

  @override
  Future<void> save(AleraSettings settings) async {
    await _db
        .into(_db.appSettingsTable)
        .insertOnConflictUpdate(
          AppSettingsTableCompanion(
            id: const Value(_rowId),
            dataJson: Value(jsonEncode(settings.toMap())),
          ),
        );
  }
}
