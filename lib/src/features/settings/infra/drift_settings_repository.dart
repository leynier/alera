import 'dart:convert';

import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:logging/logging.dart';

final Logger _log = Logger('DriftSettingsRepository');

class DriftSettingsRepository(final AleraDatabase _db)
    implements SettingsRepository {
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
    } catch (error, stackTrace) {
      // Falling back to defaults reads to the user as "my settings were
      // wiped", with nothing to confirm it or explain which row was corrupt.
      _log.severe(
        'stored settings could not be decoded; falling back to defaults',
        error,
        stackTrace,
      );
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
