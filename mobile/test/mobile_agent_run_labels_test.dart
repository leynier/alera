import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_agent_run_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers the tab title over activity text', () {
    final status = _presence(
      title: 'Map Monetization',
      state: 'waiting',
      lastAssistantMessage: '**paymentBroker**',
    );

    expect(mobileAgentRunTitle(status), 'Map Monetization');
    expect(mobileAgentRunActivity(status), '**paymentBroker**');
  });

  test('keeps working tool activity on the secondary line', () {
    final status = _presence(
      title: 'Map Monetization',
      state: 'working',
      toolName: 'Read',
      toolInput: 'lib/foo.dart',
      lastAssistantMessage: 'Ready to continue',
    );

    expect(mobileAgentRunTitle(status), 'Map Monetization');
    expect(mobileAgentRunActivity(status), 'Read: lib/foo.dart');
  });

  test('falls back to the agent name when the host omitted title', () {
    final status = _presence(
      state: 'waiting',
      lastAssistantMessage: 'Waiting for approval',
    );

    expect(mobileAgentRunTitle(status), 'Codex');
    expect(mobileAgentRunActivity(status), 'Waiting for approval');
  });

  test('omits activity when it would duplicate the title', () {
    final status = _presence(
      title: 'Map Monetization',
      state: 'done',
      lastAssistantMessage: 'Map Monetization',
    );

    expect(mobileAgentRunTitle(status), 'Map Monetization');
    expect(mobileAgentRunActivity(status), isNull);
  });

  test('omits activity when the agent has no tool or assistant text', () {
    final status = _presence(title: 'Map Monetization', state: 'waiting');

    expect(mobileAgentRunTitle(status), 'Map Monetization');
    expect(mobileAgentRunActivity(status), isNull);
  });
}

AgentPresenceSummary _presence({
  String title = '',
  required String state,
  String? toolName,
  String? toolInput,
  String? lastAssistantMessage,
}) {
  return AgentPresenceSummary(
    terminalSessionId: 'session-1',
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: 'codex',
    state: state,
    title: title,
    toolName: toolName,
    toolInput: toolInput,
    lastAssistantMessage: lastAssistantMessage,
  );
}
