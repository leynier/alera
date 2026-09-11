import 'package:alera/src/features/workbench/domain/experimental_workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old preferences keep Classic and no Experimental tools', () {
    final json = WorkbenchViewPrefs.defaults.toMap()
      ..remove('desktopLayout')
      ..remove('experimentalPanels')
      ..remove('experimentalRightSidebarWidth')
      ..remove('experimentalNewWorkspaceTools');
    final prefs = WorkbenchViewPrefs.fromJson(json);
    expect(prefs.desktopLayout, DesktopWorkspaceLayout.classic);
    expect(prefs.experimentalPanels, isEmpty);
    expect(prefs.experimentalNewWorkspaceTools, isEmpty);
  });

  test('new-workspace tools drop duplicates, unknowns, and keep order', () {
    expect(
      ExperimentalWorkspaceTool.uniqueInOrder([
        ExperimentalWorkspaceTool.sourceControl,
        ExperimentalWorkspaceTool.pullRequest,
        ExperimentalWorkspaceTool.sourceControl,
      ]),
      [
        ExperimentalWorkspaceTool.sourceControl,
        ExperimentalWorkspaceTool.pullRequest,
      ],
    );
    expect(
      ExperimentalWorkspaceTool.settingsOrder([
        ExperimentalWorkspaceTool.pullRequest,
        ExperimentalWorkspaceTool.sourceControl,
      ]),
      [
        ExperimentalWorkspaceTool.pullRequest,
        ExperimentalWorkspaceTool.sourceControl,
        ExperimentalWorkspaceTool.explorer,
        ExperimentalWorkspaceTool.search,
      ],
    );
    expect(
      ExperimentalWorkspaceTool.selectedFromOrder(
        order: ExperimentalWorkspaceTool.values,
        selected: {
          ExperimentalWorkspaceTool.pullRequest,
          ExperimentalWorkspaceTool.sourceControl,
        },
      ),
      [
        ExperimentalWorkspaceTool.sourceControl,
        ExperimentalWorkspaceTool.pullRequest,
      ],
    );
    final prefs = WorkbenchViewPrefs.fromJson({
      ...WorkbenchViewPrefs.defaults.toMap(),
      'experimentalNewWorkspaceTools': <Object?>[
        'sourceControl',
        'missing',
        'pullRequest',
        'sourceControl',
        12,
      ],
    });
    expect(prefs.experimentalNewWorkspaceTools, [
      ExperimentalWorkspaceTool.sourceControl,
      ExperimentalWorkspaceTool.pullRequest,
    ]);
    final restored = WorkbenchViewPrefs.fromJson(
      prefs
          .copyWith(
            experimentalNewWorkspaceTools: [
              ExperimentalWorkspaceTool.pullRequest,
              ExperimentalWorkspaceTool.explorer,
            ],
          )
          .toMap(),
    );
    expect(restored.experimentalNewWorkspaceTools, [
      ExperimentalWorkspaceTool.pullRequest,
      ExperimentalWorkspaceTool.explorer,
    ]);
  });

  test('fromNewWorkspaceTools opens tools in order and selects the first', () {
    final empty = ExperimentalWorkspacePanel.fromNewWorkspaceTools(
      const <ExperimentalWorkspaceTool>[],
    );
    expect(empty.tabKeys, isEmpty);
    expect(empty.activeKey, isNull);
    final panel = ExperimentalWorkspacePanel.fromNewWorkspaceTools([
      ExperimentalWorkspaceTool.sourceControl,
      ExperimentalWorkspaceTool.pullRequest,
      ExperimentalWorkspaceTool.sourceControl,
    ]);
    expect(panel.tabKeys, ['tool:sourceControl', 'tool:pullRequest']);
    expect(panel.activeKey, 'tool:sourceControl');
    final withPrimary =
        const ExperimentalWorkspacePanel(primaryTabId: 'primary')
            .openToolsInOrder([
              ExperimentalWorkspaceTool.sourceControl,
              ExperimentalWorkspaceTool.pullRequest,
            ]);
    expect(withPrimary.primaryTabId, 'primary');
    expect(withPrimary.tabKeys, ['tool:sourceControl', 'tool:pullRequest']);
    expect(withPrimary.activeKey, 'tool:sourceControl');
  });
}
