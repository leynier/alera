import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/codex_chat/application/codex_composer_draft_store.dart';
import 'package:alera/src/features/codex_chat/domain/codex_composer_draft.dart';
import 'package:alera/src/features/mobile_emulator/application/mobile_emulator_providers.dart';
import 'package:alera/src/features/mobile_emulator/domain/mobile_emulator_models.dart';
import 'package:alera/src/features/mobile_emulator/infra/mobile_emulator_service.dart';
import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_explorer_reveal.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/application/worktree_setup_service.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fake_git_backend.dart';
import 'fake_project_config.dart';

part 'workbench_controller_lifecycle_test_cases.dart';
part 'workbench_controller_tab_focus_test_cases.dart';
part 'workbench_controller_sleep_test_cases.dart';
part 'workbench_controller_layout_persistence_test_cases.dart';
part 'workbench_controller_mobile_emulator_test_cases.dart';
part 'workbench_controller_view_prefs_test_cases.dart';
part 'workbench_controller_explorer_reveal_test_cases.dart';
part 'workbench_controller_active_filter_test_cases.dart';
part 'workbench_controller_failure_test_cases.dart';
part 'workbench_controller_create_workspace_test_cases.dart';
part 'workbench_controller_workspace_graph_test_cases.dart';
part 'workbench_controller_pinning_test_cases.dart';
part 'workbench_controller_watcher_recovery_test_cases.dart';
part 'workbench_controller_navigation_test_cases.dart';
part 'workbench_controller_preview_tab_test_cases.dart';
part 'workbench_controller_view_prefs_test_repository.dart';
part 'workbench_controller_test_harness.dart';
part 'workbench_controller_selection_test_cases.dart';

late _WorkbenchHarness _harness;
late WorkbenchController _controller;

void main() {
  group('WorkbenchController', () {
    setUp(() {
      _harness = _WorkbenchHarness();
      _controller = _harness._controller;
    });

    tearDown(() async {
      await _harness.dispose();
    });

    _registerWorkbenchControllerLifecycleTests();
    _registerWorkbenchControllerTabFocusTests();
    _registerWorkbenchControllerSleepTests();
    _registerWorkbenchControllerLayoutPersistenceTests();
    _registerWorkbenchControllerMobileEmulatorTests();
    _registerWorkbenchControllerViewPrefsTests();
    _registerWorkbenchControllerExplorerRevealTests();
    _registerWorkbenchControllerActiveFilterTests();
    _registerWorkbenchControllerFailureTests();
    _registerWorkbenchControllerCreateWorkspaceTests();
    _registerWorkbenchControllerWorkspaceGraphTests();
    _registerWorkbenchControllerPinningTests();
    _registerWorkbenchControllerWatcherRecoveryTests();
    _registerWorkbenchControllerNavigationTests();
    _registerWorkbenchControllerPreviewTabTests();
  });
}
