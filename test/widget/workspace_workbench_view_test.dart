// ignore_for_file: library_private_types_in_public_api

import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_tab_attention.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/workspace_workbench_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

part 'workspace_workbench_view_helper_test_cases.dart';
part 'workspace_workbench_view_pane_test_cases.dart';
part 'workspace_workbench_view_tab_test_cases.dart';
part 'workspace_workbench_view_test_harness.dart';

late _FakeTerminalRuntime terminalRuntime;
late List<String?> createdTabs;
late List<_SelectedTabAction> selectedTabs;
late List<String> closedTabs;
late List<List<String>> closedTabGroups;
late List<String> renamedTabs;
late List<_MovedTabAction> movedTabs;
late List<_SplitGroupAction> splitGroups;
late List<String> mergedGroups;
late List<_UpdatedSplitRatioAction> updatedRatios;

void main() {
  _registerWorkspaceWorkbenchViewHelperTests();
  group('WorkspaceWorkbenchView', () {
    setUp(() {
      terminalRuntime = _FakeTerminalRuntime();
      createdTabs = <String?>[];
      selectedTabs = <_SelectedTabAction>[];
      closedTabs = <String>[];
      closedTabGroups = <List<String>>[];
      renamedTabs = <String>[];
      movedTabs = <_MovedTabAction>[];
      splitGroups = <_SplitGroupAction>[];
      mergedGroups = <String>[];
      updatedRatios = <_UpdatedSplitRatioAction>[];
    });

    _registerWorkspaceWorkbenchViewPaneTests();
    _registerWorkspaceWorkbenchViewTabTests();
  });
}
