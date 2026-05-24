import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:sembast/sembast.dart';

class SembastWorkbenchViewPrefsRepository {
  SembastWorkbenchViewPrefsRepository(this._db);

  final Database _db;

  static const String _recordKey = 'prefs';

  Future<WorkbenchViewPrefs> load() async {
    final record = await AleraStores.workbenchViewPrefs
        .record(_recordKey)
        .get(_db);
    if (record == null) {
      return WorkbenchViewPrefs.defaults;
    }
    try {
      return WorkbenchViewPrefs.fromJson(record);
    } catch (_) {
      return WorkbenchViewPrefs.defaults;
    }
  }

  Future<void> save(WorkbenchViewPrefs prefs) async {
    await AleraStores.workbenchViewPrefs
        .record(_recordKey)
        .put(_db, prefs.toJson());
  }
}
