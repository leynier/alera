import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/application/workbench_tab_attention.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 9);

  AgentStatusEntry entry(AgentStatusState state, {DateTime? stateStartedAt}) {
    return AgentStatusEntry(
      terminalSessionId: 's1',
      workspaceId: 'w1',
      tabId: 't1',
      agentType: .claude,
      state: state,
      prompt: '',
      updatedAt: now,
      stateStartedAt: stateStartedAt ?? now,
    );
  }

  group('workbenchTabAttention', () {
    test('waiting and blocked always need attention', () {
      expect(
        workbenchTabAttention(
          status: entry(.waiting),
          completionAcknowledged: false,
        ),
        WorkbenchTabAttention.agentWaiting,
      );
      expect(
        workbenchTabAttention(
          status: entry(.blocked),
          completionAcknowledged: false,
        ),
        WorkbenchTabAttention.agentBlocked,
      );
    });

    test('done needs attention until its completion is acknowledged', () {
      expect(
        workbenchTabAttention(
          status: entry(.done),
          completionAcknowledged: false,
        ),
        WorkbenchTabAttention.agentDoneUnacked,
      );
      expect(
        workbenchTabAttention(
          status: entry(.done),
          completionAcknowledged: true,
        ),
        WorkbenchTabAttention.none,
      );
    });

    test('working has no extra attention', () {
      expect(
        workbenchTabAttention(
          status: entry(.working),
          completionAcknowledged: false,
        ),
        WorkbenchTabAttention.none,
      );
    });
  });

  group('workbenchTabAttentionDotColor', () {
    test('uses warning for unacked done', () {
      expect(
        workbenchTabAttentionDotColor(
          status: entry(.done),
          completionAcknowledged: false,
        ),
        AleraTokens.warning,
      );
    });
  });

  group('WorkbenchTabCompletionAcknowledgements', () {
    test('keeps a viewed completion acknowledged across tab switches', () {
      final acknowledgements = WorkbenchTabCompletionAcknowledgements();
      final completion = entry(.done);

      expect(acknowledgements.isAcknowledged(completion), isFalse);
      acknowledgements.acknowledge(completion);
      expect(acknowledgements.isAcknowledged(completion), isTrue);
      expect(acknowledgements.isAcknowledged(completion), isTrue);
    });

    test('a later completion epoch requires acknowledgement again', () {
      final acknowledgements = WorkbenchTabCompletionAcknowledgements();
      final first = entry(.done);
      acknowledgements.acknowledge(first);
      final later = entry(
        .done,
        stateStartedAt: now.add(const Duration(minutes: 1)),
      );

      expect(acknowledgements.isAcknowledged(later), isFalse);
    });

    test('retains acknowledgements until the session is actually removed', () {
      final acknowledgements = WorkbenchTabCompletionAcknowledgements();
      final completion = entry(.done);
      acknowledgements.acknowledge(completion);

      acknowledgements.retainTerminalSessions(<String>{'s1', 's2'});
      expect(acknowledgements.isAcknowledged(completion), isTrue);

      acknowledgements.retainTerminalSessions(<String>{'s2'});
      expect(acknowledgements.isAcknowledged(completion), isFalse);
    });
  });
}
