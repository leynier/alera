import 'dart:async';

import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_explorer_reveal.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/presentation/workspace_context_sidebar.dart';
import 'package:alera/src/features/workbench/presentation/workspace_explorer.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../unit/fake_git_backend.dart';

part 'workspace_explorer_cursor_cases.dart';
part 'workspace_explorer_context_sidebar_cases.dart';
part 'workspace_explorer_git_snapshot_cases.dart';
part 'workspace_explorer_reveal_cases.dart';
part 'workspace_explorer_session_cache_cases.dart';
part 'workspace_explorer_interaction_cases.dart';
part 'workspace_explorer_context_menu_cases.dart';
part 'workspace_explorer_test_harness.dart';
part 'workspace_explorer_fake_files.dart';

void main() {
  _registerWorkspaceExplorerContextSidebarTests();
  _registerWorkspaceExplorerGitSnapshotTests();
  _registerWorkspaceExplorerRevealTests();
  _registerWorkspaceExplorerCursorTests();
  _registerWorkspaceExplorerSessionCacheTests();
  _registerWorkspaceExplorerInteractionTests();
  _registerWorkspaceExplorerContextMenuTests();
}
