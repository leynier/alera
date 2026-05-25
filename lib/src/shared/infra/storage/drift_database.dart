import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'drift_database.g.dart';

const int aleraSchemaVersion = 1;
const String aleraDatabaseFileName = 'alera.sqlite';

class ProjectsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get repoPath => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get kind => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class WorkspacesTable extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get name => text()();
  TextColumn get branch => text().nullable()();
  TextColumn get path => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get kind => text()();
  TextColumn get status => text()();
  TextColumn get sourceBranch => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class WorkspaceTabsTable extends Table {
  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get kind => text()();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class WorkbenchLayoutsTable extends Table {
  TextColumn get workspaceId => text()();
  TextColumn get dataJson => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{workspaceId};
}

class WorkbenchViewPrefsTable extends Table {
  IntColumn get id => integer()();
  TextColumn get dataJson => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class AppSettingsTable extends Table {
  IntColumn get id => integer()();
  TextColumn get dataJson => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File(p.join(dir.path, aleraDatabaseFileName));
    return NativeDatabase.createInBackground(file);
  });
}

@DriftDatabase(
  tables: <Type>[
    ProjectsTable,
    WorkspacesTable,
    WorkspaceTabsTable,
    WorkbenchLayoutsTable,
    WorkbenchViewPrefsTable,
    AppSettingsTable,
  ],
)
class AleraDatabase extends _$AleraDatabase {
  AleraDatabase({QueryExecutor? executor}) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => aleraSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) => m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {},
  );
}

Future<AleraDatabase> openAleraDb({QueryExecutor? executor}) async {
  final db = AleraDatabase(executor: executor);
  await db.customSelect('SELECT 1').get();
  return db;
}
