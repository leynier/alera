import 'dart:io';

import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Migrator, QueryRow;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  group('drift database', () {
    test('defines the expected table schemas', () {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final projects = db.projectsTable;
      final workspaces = db.workspacesTable;
      final tabs = db.workspaceTabsTable;
      final layouts = db.workbenchLayoutsTable;
      final viewPrefs = db.workbenchViewPrefsTable;
      final settings = db.appSettingsTable;
      final projectConfigs = db.projectConfigsTable;
      final appWindowState = db.appWindowStateTable;

      expect(projects.id, isNotNull);
      expect(projects.name, isNotNull);
      expect(projects.repoPath, isNotNull);
      expect(projects.createdAt, isNotNull);
      expect(projects.updatedAt, isNotNull);
      expect(projects.kind, isNotNull);
      expect(projects.primaryKey, hasLength(1));

      expect(workspaces.id, isNotNull);
      expect(workspaces.projectId, isNotNull);
      expect(workspaces.name, isNotNull);
      expect(workspaces.branch, isNotNull);
      expect(workspaces.path, isNotNull);
      expect(workspaces.createdAt, isNotNull);
      expect(workspaces.updatedAt, isNotNull);
      expect(workspaces.kind, isNotNull);
      expect(workspaces.status, isNotNull);
      expect(workspaces.sourceBranch, isNotNull);
      expect(workspaces.reusesExistingBranch, isNotNull);
      expect(workspaces.primaryKey, hasLength(1));

      expect(tabs.id, isNotNull);
      expect(tabs.workspaceId, isNotNull);
      expect(tabs.kind, isNotNull);
      expect(tabs.title, isNotNull);
      expect(tabs.createdAt, isNotNull);
      expect(tabs.updatedAt, isNotNull);
      expect(tabs.payloadJson, isNotNull);
      expect(tabs.primaryKey, hasLength(1));

      expect(layouts.workspaceId, isNotNull);
      expect(layouts.dataJson, isNotNull);
      expect(layouts.primaryKey, hasLength(1));

      expect(viewPrefs.id, isNotNull);
      expect(viewPrefs.dataJson, isNotNull);
      expect(viewPrefs.primaryKey, hasLength(1));

      expect(settings.id, isNotNull);
      expect(settings.dataJson, isNotNull);
      expect(settings.primaryKey, hasLength(1));

      expect(projectConfigs.projectId, isNotNull);
      expect(projectConfigs.dataJson, isNotNull);
      expect(projectConfigs.updatedAt, isNotNull);
      expect(projectConfigs.primaryKey, hasLength(1));

      expect(appWindowState.id, isNotNull);
      expect(appWindowState.dataJson, isNotNull);
      expect(appWindowState.updatedAt, isNotNull);
      expect(appWindowState.primaryKey, hasLength(1));
    });

    test('exposes schema version and migration hooks', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      expect(db.schemaVersion, aleraSchemaVersion);

      await db.migration.onCreate(Migrator(db));
      await db.migration.onUpgrade(Migrator(db), 1, 1);

      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
          )
          .get();
      final names = rows
          .map((row) => row.data['name'] as String)
          .where((name) => !name.startsWith('sqlite_'))
          .toSet();

      expect(
        names,
        containsAll(<String>[
          'projects_table',
          'workspaces_table',
          'workspace_tabs_table',
          'workbench_layouts_table',
          'workbench_view_prefs_table',
          'app_settings_table',
          'project_configs_table',
          'app_window_state_table',
        ]),
      );
    });

    test(
      'openAleraDb opens the default database in application support',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('alera-drift-db-');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final previousPlatform = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
        addTearDown(() => PathProviderPlatform.instance = previousPlatform);

        final db = await openAleraDb();
        addTearDown(db.close);

        expect(
          File(p.join(tempDir.path, aleraDatabaseFileName)).existsSync(),
          isTrue,
        );
        final journalMode = await db
            .customSelect('PRAGMA journal_mode')
            .getSingle();
        expect((journalMode.data.values.single as String).toLowerCase(), 'wal');
        expect(
          await db.customSelect('SELECT 1 AS value').getSingle(),
          isA<QueryRow>(),
        );
      },
    );

    test(
      'default lazy connection creates a missing application support directory',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'alera-drift-root-',
        );
        final supportPath = p.join(tempDir.path, 'nested', 'support');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final previousPlatform = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _FakePathProviderPlatform(supportPath);
        addTearDown(() => PathProviderPlatform.instance = previousPlatform);

        final db = AleraDatabase();
        addTearDown(db.close);

        expect(Directory(supportPath).existsSync(), isFalse);
        expect(
          await db.customSelect('SELECT 1 AS value').getSingle(),
          isA<QueryRow>(),
        );
        expect(Directory(supportPath).existsSync(), isTrue);
        expect(
          File(p.join(supportPath, aleraDatabaseFileName)).existsSync(),
          isTrue,
        );
      },
    );
  });
}

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.applicationSupportPath);

  final String applicationSupportPath;

  @override
  Future<String?> getApplicationSupportPath() async => applicationSupportPath;
}
