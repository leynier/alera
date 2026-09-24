import 'package:alera/src/features/workbench/domain/workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old preferences keep an empty panel and no new-workspace tools', () {
    final json = WorkbenchViewPrefs.defaults.toMap()
      ..remove('desktopLayout')
      ..remove('workspacePanels')
      ..remove('rightSidebarWidth')
      ..remove('newWorkspaceTools');
    final prefs = WorkbenchViewPrefs.fromJson(json);
    expect(prefs.workspacePanels, isEmpty);
    expect(prefs.newWorkspaceTools, isEmpty);
  });

  test('new-workspace tools drop duplicates, unknowns, and keep order', () {
    expect(
      WorkspaceTool.uniqueInOrder([
        WorkspaceTool.sourceControl,
        WorkspaceTool.pullRequest,
        WorkspaceTool.sourceControl,
      ]),
      [WorkspaceTool.sourceControl, WorkspaceTool.pullRequest],
    );
    expect(
      WorkspaceTool.settingsOrder([
        WorkspaceTool.pullRequest,
        WorkspaceTool.sourceControl,
      ]),
      [
        WorkspaceTool.pullRequest,
        WorkspaceTool.sourceControl,
        WorkspaceTool.explorer,
        WorkspaceTool.search,
      ],
    );
    expect(
      WorkspaceTool.selectedFromOrder(
        order: WorkspaceTool.values,
        selected: {WorkspaceTool.pullRequest, WorkspaceTool.sourceControl},
      ),
      [WorkspaceTool.sourceControl, WorkspaceTool.pullRequest],
    );
    final prefs = WorkbenchViewPrefs.fromJson({
      ...WorkbenchViewPrefs.defaults.toMap(),
      'newWorkspaceTools': <Object?>[
        'sourceControl',
        'missing',
        'pullRequest',
        'sourceControl',
        12,
      ],
    });
    expect(prefs.newWorkspaceTools, [
      WorkspaceTool.sourceControl,
      WorkspaceTool.pullRequest,
    ]);
    final restored = WorkbenchViewPrefs.fromJson(
      prefs
          .copyWith(
            newWorkspaceTools: [
              WorkspaceTool.pullRequest,
              WorkspaceTool.explorer,
            ],
          )
          .toMap(),
    );
    expect(restored.newWorkspaceTools, [
      WorkspaceTool.pullRequest,
      WorkspaceTool.explorer,
    ]);
  });

  test('fromNewWorkspaceTools opens tools in order and selects the first', () {
    final empty = WorkspacePanel.fromNewWorkspaceTools(const <WorkspaceTool>[]);
    expect(empty.tabKeys, isEmpty);
    expect(empty.activeKey, isNull);
    final panel = WorkspacePanel.fromNewWorkspaceTools([
      WorkspaceTool.sourceControl,
      WorkspaceTool.pullRequest,
      WorkspaceTool.sourceControl,
    ]);
    expect(panel.tabKeys, ['tool:sourceControl', 'tool:pullRequest']);
    expect(panel.activeKey, 'tool:sourceControl');
    final withPrimary = const WorkspacePanel(primaryTabId: 'primary')
        .openToolsInOrder([
          WorkspaceTool.sourceControl,
          WorkspaceTool.pullRequest,
        ]);
    expect(withPrimary.primaryTabId, 'primary');
    expect(withPrimary.tabKeys, ['tool:sourceControl', 'tool:pullRequest']);
    expect(withPrimary.activeKey, 'tool:sourceControl');
  });
}
