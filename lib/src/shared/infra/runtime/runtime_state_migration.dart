import 'dart:async';

import 'package:alera/src/features/projects/application/project_config_repository.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/infra/drift_project_config_repository.dart';
import 'package:alera/src/features/projects/infra/drift_project_repository.dart';
import 'package:alera/src/features/projects/infra/runtime_project_repository.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/infra/drift_settings_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/drift_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/runtime_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'runtime_state_migration.g.dart';

const _legacyDriftRuntimeStateMigrationKey =
    'legacy_drift_runtime_state_migrated_v1';
const _legacyDriftRuntimeSettingsMigrationKey =
    'legacy_drift_runtime_settings_migrated_v1';

@Riverpod(keepAlive: true)
RuntimeStateMigration runtimeStateMigration(Ref ref) {
  final runtimeClient = ref.watch(runtimeHostClientProvider);
  return RuntimeStateMigration(
    runtimeClient: runtimeClient,
    legacyRepositories: () async {
      final db = await ref.read(aleraDatabaseProvider.future);
      return RuntimeStateLegacyRepositories(
        projectRepository: DriftProjectRepository(db),
        projectConfigRepository: DriftProjectConfigRepository(db),
        settingsRepository: DriftSettingsRepository(db),
        workbenchRepository: DriftWorkbenchRepository(db),
      );
    },
  );
}

final class RuntimeStateLegacyRepositories {
  const RuntimeStateLegacyRepositories({
    required this.projectRepository,
    required this.projectConfigRepository,
    required this.settingsRepository,
    required this.workbenchRepository,
  });

  final ProjectRepository projectRepository;
  final ProjectConfigRepository projectConfigRepository;
  final SettingsRepository settingsRepository;
  final WorkbenchRepository workbenchRepository;
}

final class RuntimeStateMigration {
  RuntimeStateMigration({
    required RuntimeHostClient runtimeClient,
    required this.legacyRepositories,
    ProjectRepository? runtimeProjects,
    WorkbenchRepository? runtimeWorkbench,
  }) : _runtimeClient = runtimeClient,
       _runtimeProjects =
           runtimeProjects ?? RuntimeProjectRepository(runtimeClient),
       _runtimeWorkbench =
           runtimeWorkbench ?? RuntimeWorkbenchRepository(runtimeClient);

  final RuntimeHostClient _runtimeClient;
  final Future<RuntimeStateLegacyRepositories> Function() legacyRepositories;
  final ProjectRepository _runtimeProjects;
  final WorkbenchRepository _runtimeWorkbench;

  Future<void>? _migrationFuture;
  bool _completed = false;

  Future<void> ensureMigrated() {
    if (_completed) {
      return Future<void>.value();
    }
    final existing = _migrationFuture;
    if (existing != null) {
      return existing;
    }
    final next = _run().then<void>(
      (_) {
        _completed = true;
      },
      onError: (Object error, StackTrace stackTrace) {
        _migrationFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _migrationFuture = next;
    return next;
  }

  Future<void> _run() async {
    final legacy = await legacyRepositories();
    if (await _metadataValue(_legacyDriftRuntimeStateMigrationKey) != 'true') {
      await _migrateProjectsAndWorkbench(legacy);
      await _setMetadataValue(_legacyDriftRuntimeStateMigrationKey, 'true');
    }
    if (await _metadataValue(_legacyDriftRuntimeSettingsMigrationKey) !=
        'true') {
      await _migrateSettingsAndProjectConfig(legacy);
      await _setMetadataValue(_legacyDriftRuntimeSettingsMigrationKey, 'true');
    }
  }

  Future<void> _migrateProjectsAndWorkbench(
    RuntimeStateLegacyRepositories legacy,
  ) async {
    final legacyProjects = await legacy.projectRepository.listAll();
    final runtimeProjectIds = <String>{
      for (final project in await _runtimeProjects.listAll()) project.id,
    };

    for (final project in legacyProjects) {
      if (runtimeProjectIds.add(project.id)) {
        await _runtimeProjects.add(project);
      }

      final legacyWorkspaces = await legacy.workbenchRepository.listWorkspaces(
        project.id,
      );
      for (final workspace in legacyWorkspaces) {
        if (await _runtimeWorkbench.findWorkspaceById(workspace.id) == null) {
          await _runtimeWorkbench.upsertWorkspace(workspace);
        }

        final legacyTabs = await legacy.workbenchRepository.listWorkspaceTabs(
          workspace.id,
        );
        for (final tab in legacyTabs) {
          if (await _runtimeWorkbench.findWorkspaceTabById(tab.id) == null) {
            await _runtimeWorkbench.upsertWorkspaceTab(tab);
          }
        }

        final legacyLayout = await legacy.workbenchRepository
            .findWorkbenchLayout(workspace.id);
        if (legacyLayout != null &&
            await _runtimeWorkbench.findWorkbenchLayout(workspace.id) == null) {
          await _runtimeWorkbench.upsertWorkbenchLayout(legacyLayout);
        }
      }
    }
  }

  Future<void> _migrateSettingsAndProjectConfig(
    RuntimeStateLegacyRepositories legacy,
  ) async {
    final settings = await legacy.settingsRepository.load();
    await _runtimeClient
        .runtimeRequest('runtimeSettings.update', <String, Object?>{
          'workspaceDirectory': settings.general.workspaceDirectory,
          'confirmWorkspaceRemoval': settings.general.confirmWorkspaceRemoval,
        });
    final configs = await legacy.projectConfigRepository.loadAll();
    for (final entry in configs.entries) {
      await _runtimeClient.runtimeRequest(
        'projectConfig.upsert',
        <String, Object?>{
          'projectId': entry.key,
          'config': entry.value.toMap(),
        },
      );
    }
  }

  Future<String?> _metadataValue(String key) async {
    final value = await _runtimeClient.runtimeRequest(
      'runtimeMetadata.get',
      <String, Object?>{'key': key},
    );
    return value is String ? value : null;
  }

  Future<void> _setMetadataValue(String key, String value) async {
    await _runtimeClient.runtimeRequest(
      'runtimeMetadata.set',
      <String, Object?>{'key': key, 'value': value},
    );
  }
}
