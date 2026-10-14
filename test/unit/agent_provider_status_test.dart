import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_status.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_list_row.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final checkedAt = DateTime.utc(2026, 10, 13, 12);

  AgentChatProviderInstance row({
    bool enabled = true,
    bool available = true,
    bool? installed = true,
    bool setupRequired = false,
    AgentChatProviderAuth auth = const AgentChatProviderAuth(),
    String? unavailableReason,
  }) => AgentChatProviderInstance(
    id: 'claudeAgent',
    provider: 'claudeAgent',
    label: 'Claude',
    enabled: enabled,
    available: available,
    installed: installed,
    setupRequired: setupRequired,
    auth: auth,
    unavailableReason: unavailableReason,
  );

  group('agentProviderStatusOf', () {
    test('reads Ready only from a verified sign-in', () {
      final status = agentProviderStatusOf(
        row(
          auth: AgentChatProviderAuth(status: .signedIn, checkedAt: checkedAt),
        ),
      );
      expect(status.kind, AgentProviderStatusKind.ready);
      expect(status.label, 'Ready');
    });

    test('an available provider without a verified sign-in is unknown', () {
      expect(
        agentProviderStatusOf(row()).kind,
        AgentProviderStatusKind.unknownSignIn,
      );
      // A signed-in claim with no check time is not proof either.
      expect(
        agentProviderStatusOf(
          row(auth: const AgentChatProviderAuth(status: .signedIn)),
        ).kind,
        AgentProviderStatusKind.unknownSignIn,
      );
    });

    test('a verified sign-out asks for sign-in', () {
      expect(
        agentProviderStatusOf(
          row(
            available: false,
            auth: AgentChatProviderAuth(
              status: .signedOut,
              checkedAt: checkedAt,
            ),
          ),
        ).kind,
        AgentProviderStatusKind.signInNeeded,
      );
    });

    test('off, checking, not installed and error take precedence in order', () {
      expect(
        agentProviderStatusOf(row(enabled: false), checking: true).kind,
        AgentProviderStatusKind.off,
      );
      expect(
        agentProviderStatusOf(row(), checking: true).kind,
        AgentProviderStatusKind.checking,
      );
      expect(
        agentProviderStatusOf(row(installed: false, available: false)).kind,
        AgentProviderStatusKind.notInstalled,
      );
      final error = agentProviderStatusOf(
        row(available: false, unavailableReason: 'Bad executable path.'),
      );
      expect(error.kind, AgentProviderStatusKind.error);
      expect(error.detail, 'Bad executable path.');
      expect(
        agentProviderStatusTone(AgentProviderStatusKind.error),
        AleraBadgeTone.error,
      );
    });

    test('an unconfigured instance reads Setup Required, not Error', () {
      final status = agentProviderStatusOf(
        row(
          installed: null,
          available: false,
          setupRequired: true,
          unavailableReason: 'Launch failed: /private/path agent-cmd',
        ),
      );
      expect(status.kind, AgentProviderStatusKind.setupRequired);
      expect(status.label, 'Setup Required');
      // A fixed sentence, never the host's reason.
      expect(status.detail, agentProviderSetupRequiredDetail);
      expect(status.detail, isNot(contains('/private/path')));
      expect(
        agentProviderStatusTone(AgentProviderStatusKind.setupRequired),
        AleraBadgeTone.attention,
      );
    });

    test('Off and Checking still win over Setup Required', () {
      expect(
        agentProviderStatusOf(row(enabled: false, setupRequired: true)).kind,
        AgentProviderStatusKind.off,
      );
      expect(
        agentProviderStatusOf(row(setupRequired: true), checking: true).kind,
        AgentProviderStatusKind.checking,
      );
    });

    test('a configured but invalid instance stays a generic error', () {
      final status = agentProviderStatusOf(
        row(installed: null, available: false),
      );
      expect(status.kind, AgentProviderStatusKind.error);
      expect(status.detail, 'The runtime cannot start this provider.');
    });
  });

  group('agentProviderCheckedLabel', () {
    test('ages in minutes, hours and days', () {
      final now = checkedAt;
      expect(agentProviderCheckedLabel(null, now), 'Not checked yet');
      expect(agentProviderCheckedLabel(now, now), 'Checked just now');
      expect(
        agentProviderCheckedLabel(
          now.subtract(const Duration(minutes: 2)),
          now,
        ),
        'Checked 2m ago',
      );
      expect(
        agentProviderCheckedLabel(now.subtract(const Duration(hours: 3)), now),
        'Checked 3h ago',
      );
      expect(
        agentProviderCheckedLabel(now.subtract(const Duration(days: 2)), now),
        'Checked 2d ago',
      );
      // Clock skew between hosts never reads as a negative age.
      expect(
        agentProviderCheckedLabel(now.add(const Duration(minutes: 5)), now),
        'Checked just now',
      );
    });

    test('the host-wide label reports the oldest check', () {
      final older = checkedAt.subtract(const Duration(hours: 1));
      final rows = <AgentChatProviderInstance>[
        AgentChatProviderInstance(
          id: 'codex',
          provider: 'codex',
          label: 'Codex',
          checkedAt: checkedAt,
        ),
        AgentChatProviderInstance(
          id: 'pi',
          provider: 'pi',
          label: 'Pi',
          checkedAt: older,
        ),
        const AgentChatProviderInstance(
          id: 'grok',
          provider: 'grok',
          label: 'Grok',
        ),
      ];
      expect(agentProviderOldestCheck(rows), older);
    });
  });
}
