import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/presentation/widgets/agent_run_status_badge.dart';
import 'package:flutter_test/flutter_test.dart';

AgentStatusEntry _status(AgentStatusState state, {bool? interrupted}) =>
    AgentStatusEntry(
      terminalSessionId: 'tab-1',
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
      agentType: .codex,
      state: state,
      prompt: '',
      interrupted: interrupted,
      updatedAt: .utc(2026, 10, 4),
      stateStartedAt: .utc(2026, 10, 4),
    );

void main() {
  test('states that need attention or report a finished turn get a label', () {
    expect(agentRunStatusBadge(_status(.waiting)), (
      'Needs Input',
      AleraBadgeTone.attention,
    ));
    expect(agentRunStatusBadge(_status(.blocked)), (
      'Blocked',
      AleraBadgeTone.error,
    ));
    expect(agentRunStatusBadge(_status(.done)), (
      'Done',
      AleraBadgeTone.success,
    ));
  });

  test('an interrupted run is labeled over its reported state', () {
    expect(agentRunStatusBadge(_status(.done, interrupted: true)), (
      'Interrupted',
      AleraBadgeTone.error,
    ));
  });

  test('working and idle runs get no label', () {
    expect(agentRunStatusBadge(_status(.working)), isNull);
    expect(agentRunStatusBadge(null), isNull);
  });
}
