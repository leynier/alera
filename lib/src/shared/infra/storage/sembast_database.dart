import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

const int aleraSchemaVersion = 1;

const String aleraDatabaseFileName = 'alera.db';

/// Opens (or creates) the Alera Sembast database in the application support
/// directory. The database is created lazily and the schema version is stored
/// in the `meta` store under the `schemaVersion` key.
Future<Database> openAleraDb({DatabaseFactory? factory, String? path}) async {
  final resolvedFactory = factory ?? databaseFactoryIo;
  final resolvedPath = path ?? await _defaultDatabasePath();
  final db = await resolvedFactory.openDatabase(resolvedPath);
  await _ensureSchemaVersion(db);
  return db;
}

Future<String> _defaultDatabasePath() async {
  final dir = await getApplicationSupportDirectory();
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return p.join(dir.path, aleraDatabaseFileName);
}

Future<void> _ensureSchemaVersion(Database db) async {
  final meta = StoreRef<String, Object?>('meta');
  final stored = await meta.record('schemaVersion').get(db);
  if (stored is int && stored == aleraSchemaVersion) {
    return;
  }
  await meta.record('schemaVersion').put(db, aleraSchemaVersion);
}

/// Convenience accessors for the canonical Alera stores.
class AleraStores {
  AleraStores._();

  static final StoreRef<String, Map<String, Object?>> projects =
      stringMapStoreFactory.store('projects');

  static final StoreRef<String, Map<String, Object?>> workbenchWorkspaces =
      stringMapStoreFactory.store('workbench_workspaces');

  static final StoreRef<String, Map<String, Object?>> workbenchTabs =
      stringMapStoreFactory.store('workbench_tabs');

  static final StoreRef<String, Map<String, Object?>> workbenchLayouts =
      stringMapStoreFactory.store('workbench_layouts');

  static final StoreRef<String, Map<String, Object?>> terminalTabs =
      stringMapStoreFactory.store('terminal_tabs');

  static final StoreRef<String, Map<String, Object?>> workbenchViewPrefs =
      stringMapStoreFactory.store('workbench_view_prefs');

  static final StoreRef<String, Object?> meta = StoreRef<String, Object?>(
    'meta',
  );
}

bool isWindowsPlatform() => Platform.isWindows;
