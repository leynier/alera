import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:sembast/sembast.dart';

class SembastSettingsRepository implements SettingsRepository {
  SembastSettingsRepository(this._db);

  final Database _db;

  static const String _recordKey = 'settings';

  @override
  Future<AleraSettings> load() async {
    final record = await AleraStores.settings.record(_recordKey).get(_db);
    if (record == null) {
      return AleraSettings.defaults;
    }
    try {
      return AleraSettings.fromJson(record);
    } catch (_) {
      return AleraSettings.defaults;
    }
  }

  @override
  Future<void> save(AleraSettings settings) async {
    await AleraStores.settings.record(_recordKey).put(_db, settings.toJson());
  }
}
