import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AgentStatusEntry copyWith preserves nullable fields by default', () {
    final updatedAt = DateTime.utc(2026, 5, 28);
    final entry = AgentStatusEntry(
      terminalSessionId: 'session-1',
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
      agentType: AgentType.codex,
      state: AgentStatusState.working,
      prompt: 'Run tests',
      updatedAt: updatedAt,
      stateStartedAt: updatedAt,
      interrupted: true,
    );

    final copy = entry.copyWith(prompt: 'Run all tests');

    expect(copy.prompt, 'Run all tests');
    expect(copy.updatedAt, updatedAt);
    expect(copy.interrupted, isTrue);
  });
}
