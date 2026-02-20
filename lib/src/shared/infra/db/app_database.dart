import 'package:drift/drift.dart';

class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy();

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const <TableInfo<Table, Object?>>[];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const <DatabaseSchemaEntity>[];

  Future<void> initialize() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS allowlist_entries (
        scope TEXT NOT NULL,
        scope_key TEXT NOT NULL,
        command_pattern TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY(scope, scope_key, command_pattern)
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> upsertSetting(String key, String value) {
    return customStatement(
      'INSERT INTO app_settings(key, value) VALUES(?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      <Object>[key, value],
    );
  }

  Future<String?> readSetting(String key) async {
    final result = await customSelect(
      'SELECT value FROM app_settings WHERE key = ?',
      variables: <Variable<Object>>[Variable<Object>(key)],
    ).getSingleOrNull();
    return result?.read<String>('value');
  }
}
