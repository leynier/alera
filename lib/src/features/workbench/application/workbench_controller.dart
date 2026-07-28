import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/application/agent_status_providers.dart';
import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/application/workspace_browser_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_activity_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_focus_history.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'workbench_controller.g.dart';
part 'workbench_controller_internals.dart';
part 'workbench_controller_browser.dart';
part 'workbench_controller_projects.dart';
part 'workbench_controller_tab_opening.dart';
part 'workbench_controller_tabs.dart';
part 'workbench_controller_view_prefs.dart';
part 'workbench_controller_sync.dart';

@Riverpod(keepAlive: true)
class WorkbenchController extends _$WorkbenchController
    with
        _WorkbenchControllerInternals,
        _WorkbenchControllerBrowser,
        _WorkbenchControllerProjects,
        _WorkbenchControllerTabOpening,
        _WorkbenchControllerTabs,
        _WorkbenchControllerViewPrefs,
        _WorkbenchControllerSync {
  @override
  WorkbenchState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      unawaited(_projectsSub?.cancel());
      unawaited(_viewPrefsSub?.cancel());
      for (final subscription in _workspaceSubs.values) {
        unawaited(subscription.cancel());
      }
      for (final subscription in _tabSubs.values) {
        unawaited(subscription.cancel());
      }
    });
    return const WorkbenchState();
  }

  Future<void> bootstrap() async {
    if (_bootstrapStarted) {
      return;
    }
    _bootstrapStarted = true;
    try {
      final repo = _viewPrefsRepository;
      if (repo != null) {
        try {
          final prefs = await repo.load();
          state = state.copyWith(viewPrefs: prefs);
          _viewPrefsSub = repo.changes.listen((prefs) {
            if (!_disposed) state = state.copyWith(viewPrefs: prefs);
          });
        } catch (_) {
          // Fall back to defaults if loading fails; never block bootstrap.
        }
      }
      _projectsSub = _projectsService.projectRepository.watchAll().listen(
        _onProjectsChanged,
        // A dead watcher is never re-created, so a stream that errors or
        // completes must not leave a stale subscription behind.
        onError: (Object _) {},
        onDone: () => _projectsSub = null,
        cancelOnError: false,
      );
      final initialProjects = await _projectsService.projectRepository
          .listAll();
      _onProjectsChanged(initialProjects);
      await Future.wait<void>(
        initialProjects.map(_ensureMainWorkspaceForProject),
      );
      state = state.copyWith(bootstrapped: true, error: null);
    } catch (error) {
      state = state.copyWith(
        bootstrapped: true,
        error: 'Failed to bootstrap workbench: $error',
      );
    }
  }
}
