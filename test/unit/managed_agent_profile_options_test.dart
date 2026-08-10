import 'package:alera/src/features/agent_profiles/domain/managed_agent_profile_options.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('managed agent option catalogs', () {
    test('declare stable values and labels', () {
      final catalogs = <List<ManagedAgentOption>>[
        codexEffortOptions,
        claudeEffortOptions,
        copilotEffortOptions,
        basicEffortOptions,
        codexSandboxOptions,
        codexApprovalOptions,
        claudePermissionOptions,
        copilotModeOptions,
        copilotContextOptions,
        cursorModeOptions,
        cursorPermissionOptions,
        cursorSandboxOptions,
        agyModeOptions,
        piThinkingOptions,
        piTrustOptions,
        ampModeOptions,
      ];

      for (final catalog in catalogs) {
        expect(catalog, isNotEmpty);
        expect(catalog.every((option) => option.value.isNotEmpty), isTrue);
        expect(catalog.every((option) => option.label.isNotEmpty), isTrue);
        expect(
          catalog.map((option) => option.value).toSet(),
          hasLength(catalog.length),
        );
      }
    });

    test('reports model and persona support for every agent', () {
      expect(
        <AgentType, bool>{
          for (final adapter in AgentType.values)
            adapter: agentProfileSupportsModel(adapter),
        },
        <AgentType, bool>{
          AgentType.codex: true,
          AgentType.claude: true,
          AgentType.copilot: true,
          AgentType.cursor: true,
          AgentType.agy: true,
          AgentType.opencode: true,
          AgentType.opencode2: true,
          AgentType.pi: true,
          AgentType.amp: false,
          AgentType.grok: true,
        },
      );
      expect(
        <AgentType, bool>{
          for (final adapter in AgentType.values)
            adapter: agentProfileSupportsPersona(adapter),
        },
        <AgentType, bool>{
          AgentType.codex: false,
          AgentType.claude: true,
          AgentType.copilot: true,
          AgentType.cursor: false,
          AgentType.agy: true,
          AgentType.opencode: true,
          AgentType.opencode2: true,
          AgentType.pi: false,
          AgentType.amp: false,
          AgentType.grok: false,
        },
      );
    });
  });

  group('managed agent risk', () {
    test('scores every reduced-protection setting', () {
      expect(
        managedAgentRiskScore(AgentType.codex, const <String, Object?>{
          'bypassApprovalsAndSandbox': true,
          'sandbox': 'danger-full-access',
          'approvalPolicy': 'never',
        }),
        170,
      );
      expect(
        managedAgentRiskScore(AgentType.claude, const <String, Object?>{
          'permissionMode': 'bypassPermissions',
        }),
        100,
      );
      expect(
        managedAgentRiskScore(AgentType.claude, const <String, Object?>{
          'permissionMode': 'dontAsk',
        }),
        40,
      );
      expect(
        managedAgentRiskScore(AgentType.claude, const <String, Object?>{
          'allowSkipPermissions': true,
        }),
        30,
      );
      expect(
        managedAgentRiskScore(AgentType.copilot, const <String, Object?>{
          'allowAll': true,
          'mode': 'autopilot',
          'noAskUser': true,
        }),
        140,
      );
      expect(
        managedAgentRiskScore(AgentType.cursor, const <String, Object?>{
          'permissionMode': 'force',
          'sandbox': 'disabled',
          'trustWorkspace': true,
        }),
        140,
      );
      expect(
        managedAgentRiskScore(AgentType.agy, const <String, Object?>{
          'skipPermissions': true,
        }),
        100,
      );
      expect(
        managedAgentRiskScore(AgentType.opencode, const <String, Object?>{
          'autoApprove': true,
        }),
        60,
      );
      expect(
        managedAgentRiskScore(AgentType.pi, const <String, Object?>{
          'projectTrust': 'approve',
        }),
        30,
      );
      expect(managedAgentRiskScore(AgentType.amp, const {}), 0);
      expect(managedAgentRiskScore(AgentType.grok, const {}), 0);
      expect(managedAgentRiskScore(AgentType.codex, const {}), 0);
    });

    test('names every active risk marker', () {
      expect(
        managedAgentRiskMarkers(AgentType.codex, const <String, Object?>{
          'bypassApprovalsAndSandbox': true,
          'sandbox': 'danger-full-access',
          'approvalPolicy': 'never',
        }),
        <String>{'bypassApprovalsAndSandbox', 'dangerFullAccess', 'neverAsk'},
      );
      expect(
        managedAgentRiskMarkers(AgentType.claude, const <String, Object?>{
          'permissionMode': 'bypassPermissions',
        }),
        <String>{'bypassPermissions'},
      );
      expect(
        managedAgentRiskMarkers(AgentType.claude, const <String, Object?>{
          'permissionMode': 'dontAsk',
        }),
        <String>{'dontAsk'},
      );
      expect(
        managedAgentRiskMarkers(AgentType.claude, const <String, Object?>{
          'allowSkipPermissions': true,
        }),
        <String>{'allowSkipPermissions'},
      );
      expect(
        managedAgentRiskMarkers(AgentType.copilot, const <String, Object?>{
          'allowAll': true,
          'mode': 'autopilot',
          'noAskUser': true,
        }),
        <String>{'allowAll', 'autopilot', 'noAskUser'},
      );
      expect(
        managedAgentRiskMarkers(AgentType.cursor, const <String, Object?>{
          'permissionMode': 'force',
          'sandbox': 'disabled',
          'trustWorkspace': true,
        }),
        <String>{'force', 'sandboxDisabled', 'trustWorkspace'},
      );
      expect(
        managedAgentRiskMarkers(AgentType.agy, const <String, Object?>{
          'skipPermissions': true,
        }),
        <String>{'skipPermissions'},
      );
      expect(
        managedAgentRiskMarkers(AgentType.opencode, const <String, Object?>{
          'autoApprove': true,
        }),
        <String>{'autoApprove'},
      );
      expect(
        managedAgentRiskMarkers(AgentType.pi, const <String, Object?>{
          'projectTrust': 'approve',
        }),
        <String>{'projectTrust'},
      );
      expect(managedAgentRiskMarkers(AgentType.amp, const {}), isEmpty);
      expect(managedAgentRiskMarkers(AgentType.grok, const {}), isEmpty);
      expect(managedAgentRiskMarkers(AgentType.codex, const {}), isEmpty);
    });

    test('provides an adapter-specific warning', () {
      expect(
        managedAgentRiskWarning(AgentType.codex, const {
          'bypassApprovalsAndSandbox': true,
        }),
        contains('bypass Codex'),
      );
      expect(
        managedAgentRiskWarning(AgentType.codex, const {}),
        contains('reduces Codex'),
      );
      expect(
        <AgentType, String>{
          for (final adapter in AgentType.values)
            if (adapter != AgentType.codex)
              adapter: managedAgentRiskWarning(adapter, const {}),
        },
        <AgentType, String>{
          AgentType.claude:
              'This profile lets Claude continue with reduced permission prompts.',
          AgentType.copilot:
              'This profile lets Copilot take broader actions with less supervision.',
          AgentType.cursor:
              'This profile reduces Cursor review, sandbox, or trust protections.',
          AgentType.agy:
              'This profile lets Antigravity skip permission checks.',
          AgentType.opencode:
              'This profile lets OpenCode approve actions automatically.',
          AgentType.opencode2:
              'This profile lets OpenCode approve actions automatically.',
          AgentType.pi: 'This profile pre-approves project trust for Pi.',
          AgentType.amp: '',
          AgentType.grok: '',
        },
      );
    });
  });

  group('managed agent command preview', () {
    test('renders Codex approval and bypass modes', () {
      expect(
        managedAgentCommandPreview(AgentType.codex, const <String, Object?>{
          'model': 'gpt model',
          'effort': 'high',
          'sandbox': 'danger-full-access',
          'approvalPolicy': 'never',
          'webSearch': true,
        }),
        "codex --model 'gpt model' --config model_reasoning_effort=high "
        '--sandbox danger-full-access --ask-for-approval never --search',
      );
      expect(
        managedAgentCommandPreview(AgentType.codex, const <String, Object?>{
          'bypassApprovalsAndSandbox': true,
        }),
        'codex --dangerously-bypass-approvals-and-sandbox',
      );
      expect(
        managedAgentCommandPreview(AgentType.codex, const <String, Object?>{
          'effort': 'medium',
          'planModeEffort': 'xhigh',
        }),
        'codex --config model_reasoning_effort=medium '
        '--config plan_mode_reasoning_effort=xhigh',
      );
    });

    test('renders Claude and Copilot options', () {
      expect(
        managedAgentCommandPreview(AgentType.claude, const <String, Object?>{
          'model': 'sonnet',
          'effort': 'high',
          'agent': "reviewer's agent",
          'permissionMode': 'acceptEdits',
        }),
        "claude --model sonnet --effort high --agent "
        "'reviewer'\"'\"'s agent' --permission-mode acceptEdits",
      );
      expect(
        managedAgentCommandPreview(AgentType.claude, const <String, Object?>{
          'permissionMode': 'plan',
          'allowSkipPermissions': true,
        }),
        'claude --permission-mode plan '
        '--allow-dangerously-skip-permissions',
      );
      expect(
        managedAgentCommandPreview(AgentType.copilot, const <String, Object?>{
          'model': 'gpt-5',
          'effort': 'xhigh',
          'agent': 'review',
          'mode': 'autopilot',
          'context': 'long_context',
          'allowAll': true,
          'maxAiCredits': 12.5,
          'maxAutopilotContinues': 4,
          'noAskUser': true,
        }),
        'copilot --model gpt-5 --effort xhigh --agent review '
        '--mode autopilot --context long_context --allow-all '
        '--max-ai-credits 12.5 --max-autopilot-continues 4 --no-ask-user',
      );
    });

    test('routes Claude through a CCS profile when one is configured', () {
      expect(
        managedAgentCommandPreview(AgentType.claude, const <String, Object?>{
          'ccsProfile': 'work',
          'model': 'opus',
          'permissionMode': 'acceptEdits',
        }),
        'ccs work --model opus --permission-mode acceptEdits',
      );
      expect(
        managedAgentCommandPreview(AgentType.claude, const <String, Object?>{
          'ccsProfile': '   ',
          'model': 'opus',
        }),
        'claude --model opus',
      );
      expect(
        <AgentType, bool>{
          for (final adapter in AgentType.values)
            adapter: agentProfileSupportsCcsProfile(adapter),
        },
        <AgentType, bool>{
          AgentType.codex: false,
          AgentType.claude: true,
          AgentType.copilot: false,
          AgentType.cursor: false,
          AgentType.agy: false,
          AgentType.opencode: false,
          AgentType.opencode2: false,
          AgentType.pi: false,
          AgentType.amp: false,
          AgentType.grok: false,
        },
      );
    });

    test('renders every Cursor permission branch', () {
      expect(
        managedAgentCommandPreview(AgentType.cursor, const <String, Object?>{
          'model': 'composer',
          'mode': 'plan',
          'permissionMode': 'autoReview',
          'sandbox': 'enabled',
          'trustWorkspace': true,
        }),
        'cursor-agent --model composer --mode plan --auto-review '
        '--sandbox enabled --trust',
      );
      expect(
        managedAgentCommandPreview(AgentType.cursor, const <String, Object?>{
          'permissionMode': 'force',
        }),
        'cursor-agent --force',
      );
      expect(
        managedAgentCommandPreview(AgentType.cursor, const <String, Object?>{
          'permissionMode': 'manual',
        }),
        'cursor-agent',
      );
    });

    test('renders Agy, OpenCode, Pi, Amp, and Grok options', () {
      expect(
        managedAgentCommandPreview(AgentType.agy, const <String, Object?>{
          'model': 'gemini',
          'effort': 'medium',
          'agent': 'builder',
          'mode': 'accept-edits',
          'skipPermissions': true,
          'sandbox': true,
        }),
        'agy --model gemini --effort medium --agent builder '
        '--mode accept-edits --dangerously-skip-permissions --sandbox',
      );
      expect(
        managedAgentCommandPreview(AgentType.opencode, const <String, Object?>{
          'model': 'gpt',
          'agent': 'build',
          'autoApprove': true,
        }),
        'opencode --model gpt --agent build --auto',
      );
      expect(
        managedAgentCommandPreview(AgentType.opencode2, const <String, Object?>{
          'model': 'gpt',
          'agent': 'build',
          'autoApprove': true,
        }),
        // Interactive opencode2 only accepts --auto on the default TUI.
        'opencode2 --auto',
      );
      expect(
        managedAgentCommandPreview(AgentType.pi, const <String, Object?>{
          'model': 'pi-model',
          'thinking': 'xhigh',
          'projectTrust': 'approve',
        }),
        'pi --model pi-model --thinking xhigh --approve',
      );
      expect(
        managedAgentCommandPreview(AgentType.pi, const <String, Object?>{
          'projectTrust': 'ignore',
        }),
        'pi --no-approve',
      );
      expect(
        managedAgentCommandPreview(AgentType.pi, const <String, Object?>{
          'projectTrust': 'ask',
        }),
        'pi',
      );
      expect(
        managedAgentCommandPreview(AgentType.amp, const <String, Object?>{
          'mode': 'ultra',
          'fast': true,
        }),
        'amp --mode ultra --fast',
      );
      expect(managedAgentCommandPreview(AgentType.grok, const {}), 'grok');
    });

    test('ignores blank or incorrectly typed optional values', () {
      expect(
        managedAgentCommandPreview(AgentType.copilot, const <String, Object?>{
          'model': '   ',
          'effort': 4,
          'allowAll': false,
          'maxAiCredits': 'unlimited',
        }),
        'copilot',
      );
      expect(managedAgentCommandPreview(AgentType.codex, const {}), 'codex');
    });
  });
}
