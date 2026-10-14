import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/application/workspace_details_agent_groups.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = .utc(2026, 10, 13, 12);

WorkspaceAgentRun _run(
  String id,
  AgentStatusState state, {
  Duration age = Duration.zero,
  bool? interrupted,
}) => WorkspaceAgentRun(
  tab: WorkspaceTabRecord(
    id: id,
    workspaceId: 'w',
    title: id,
    createdAt: _now,
    updatedAt: _now,
  ),
  status: AgentStatusEntry(
    terminalSessionId: id,
    workspaceId: 'w',
    tabId: id,
    agentType: .codex,
    state: state,
    prompt: 'Prompt',
    updatedAt: _now.subtract(age),
    stateStartedAt: _now.subtract(age),
    interrupted: interrupted,
  ),
);

List<String> _ids(List<WorkspaceAgentRun> runs) => [
  for (final run in runs) run.tab.id,
];

void main() {
  test('runs order like the Agent Activity sort', () {
    final groups = groupWorkspaceDetailsAgentRuns(
      [
        _run('working', .working),
        _run('done-old', .done, age: const Duration(minutes: 5)),
        _run('stale', .waiting, age: const Duration(hours: 1)),
        _run('interrupted', .working, interrupted: true),
        _run('done-new', .done),
        _run('waiting', .waiting, age: const Duration(minutes: 1)),
      ],
      panel: null,
      now: _now,
    );
    expect(_ids(groups.main), [
      'interrupted',
      'waiting',
      'done-new',
      'done-old',
      'working',
      'stale',
    ]);
    expect(groups.right, isEmpty);
  });

  test('equal activity keeps the tab order', () {
    final groups = groupWorkspaceDetailsAgentRuns(
      [_run('first', .done), _run('second', .done)],
      panel: null,
      now: _now,
    );
    expect(_ids(groups.main), ['first', 'second']);
  });

  test('tabs outside the main panel belong to the right panel', () {
    final panel = WorkspacePanel(
      mainLayout: WorkbenchLayout.single(
        workspaceId: 'w',
        tabIds: [WorkspacePanel.tabKey('main')],
      ),
    );
    final groups = groupWorkspaceDetailsAgentRuns(
      [_run('side', .waiting), _run('main', .done)],
      panel: panel,
      now: _now,
    );
    expect(_ids(groups.main), ['main']);
    expect(_ids(groups.right), ['side']);
    expect(_ids(groups.all), ['main', 'side']);
    expect(_ids(groups.runsIn(.right)), ['side']);
  });
}
