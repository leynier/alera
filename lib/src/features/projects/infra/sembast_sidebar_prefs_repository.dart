import 'package:alera/src/features/projects/domain/sidebar_prefs.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:sembast/sembast.dart';

class SembastSidebarPrefsRepository {
  SembastSidebarPrefsRepository(this._db);

  final Database _db;

  static const String _recordKey = 'prefs';

  Future<SidebarPrefs> load() async {
    final record = await AleraStores.sidebarPrefs.record(_recordKey).get(_db);
    if (record == null) {
      return SidebarPrefs.defaults;
    }
    try {
      return SidebarPrefs.fromJson(record);
    } catch (_) {
      return SidebarPrefs.defaults;
    }
  }

  Future<void> save(SidebarPrefs prefs) async {
    await AleraStores.sidebarPrefs.record(_recordKey).put(_db, prefs.toJson());
  }
}
