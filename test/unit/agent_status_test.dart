import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_test/flutter_test.dart';

AgentStatusEntry _entry({
  AgentStatusState state = AgentStatusState.working,
  String prompt = 'Run tests',
  String? toolName = 'bash',
  bool? interrupted,
}) {
  final updatedAt = DateTime.utc(2026, 5, 28);
  return AgentStatusEntry(
    terminalSessionId: 'session-1',
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: AgentType.codex,
    state: state,
    prompt: prompt,
    updatedAt: updatedAt,
    stateStartedAt: updatedAt,
    toolName: toolName,
    interrupted: interrupted,
  );
}

void main() {
  test('AgentStatusEntry compares by value', () {
    // Without this every host snapshot builds fresh objects, so no Riverpod
    // short-circuit can fire and an unchanged snapshot rebuilds the sidebar.
    expect(_entry(), _entry());
    expect(_entry().hashCode, _entry().hashCode);
  });

  test('AgentStatusEntry differs when any field differs', () {
    expect(_entry(), isNot(_entry(state: AgentStatusState.done)));
    expect(_entry(), isNot(_entry(prompt: 'Other')));
    expect(_entry(), isNot(_entry(toolName: 'grep')));
    expect(_entry(), isNot(_entry(interrupted: true)));
  });

  test('AgentStatusEntry copyWith can null a field explicitly', () {
    // Guards the migration from the hand-written sentinel to the generated
    // one: passing null must mean "clear", not "keep".
    expect(_entry().copyWith(toolName: null).toolName, isNull);
    expect(
      _entry(interrupted: true).copyWith(interrupted: null).interrupted,
      isNull,
    );
  });

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
