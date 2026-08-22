import 'package:alera/src/features/agent_profiles/domain/agent_profile_adapters.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';

class ManagedAgentOption {
  const ManagedAgentOption(this.value, this.label);

  final String value;
  final String label;
}

const List<ManagedAgentOption> codexEffortOptions = <ManagedAgentOption>[
  ManagedAgentOption('minimal', 'Minimal'),
  ManagedAgentOption('low', 'Low'),
  ManagedAgentOption('medium', 'Medium'),
  ManagedAgentOption('high', 'High'),
  ManagedAgentOption('xhigh', 'Extra High'),
  ManagedAgentOption('max', 'Max'),
  ManagedAgentOption('ultra', 'Ultra'),
];

const List<ManagedAgentOption> claudeEffortOptions = <ManagedAgentOption>[
  ManagedAgentOption('low', 'Low'),
  ManagedAgentOption('medium', 'Medium'),
  ManagedAgentOption('high', 'High'),
  ManagedAgentOption('xhigh', 'Extra High'),
  ManagedAgentOption('max', 'Max'),
];

const List<ManagedAgentOption> copilotEffortOptions = <ManagedAgentOption>[
  ManagedAgentOption('none', 'None'),
  ManagedAgentOption('minimal', 'Minimal'),
  ManagedAgentOption('low', 'Low'),
  ManagedAgentOption('medium', 'Medium'),
  ManagedAgentOption('high', 'High'),
  ManagedAgentOption('xhigh', 'Extra High'),
  ManagedAgentOption('max', 'Max'),
];

const List<ManagedAgentOption> basicEffortOptions = <ManagedAgentOption>[
  ManagedAgentOption('low', 'Low'),
  ManagedAgentOption('medium', 'Medium'),
  ManagedAgentOption('high', 'High'),
];

const List<ManagedAgentOption> codexSandboxOptions = <ManagedAgentOption>[
  ManagedAgentOption('read-only', 'Read Only'),
  ManagedAgentOption('workspace-write', 'Workspace Write'),
  ManagedAgentOption('danger-full-access', 'Full Access'),
];

const List<ManagedAgentOption> codexApprovalOptions = <ManagedAgentOption>[
  ManagedAgentOption('untrusted', 'Untrusted'),
  ManagedAgentOption('on-request', 'On Request'),
  ManagedAgentOption('never', 'Never Ask'),
];

const List<ManagedAgentOption> claudePermissionOptions = <ManagedAgentOption>[
  ManagedAgentOption('acceptEdits', 'Accept Edits'),
  ManagedAgentOption('auto', 'Auto'),
  ManagedAgentOption('bypassPermissions', 'Bypass Permissions'),
  ManagedAgentOption('manual', 'Manual'),
  ManagedAgentOption('dontAsk', 'Do Not Ask'),
  ManagedAgentOption('plan', 'Plan'),
];

const List<ManagedAgentOption> copilotModeOptions = <ManagedAgentOption>[
  ManagedAgentOption('interactive', 'Interactive'),
  ManagedAgentOption('plan', 'Plan'),
  ManagedAgentOption('autopilot', 'Autopilot'),
];

const List<ManagedAgentOption> copilotContextOptions = <ManagedAgentOption>[
  ManagedAgentOption('default', 'Default Context'),
  ManagedAgentOption('long_context', 'Long Context'),
];

const List<ManagedAgentOption> cursorModeOptions = <ManagedAgentOption>[
  ManagedAgentOption('plan', 'Plan'),
  ManagedAgentOption('ask', 'Ask'),
];

const List<ManagedAgentOption> cursorPermissionOptions = <ManagedAgentOption>[
  ManagedAgentOption('autoReview', 'Auto Review'),
  ManagedAgentOption('force', 'Force'),
];

const List<ManagedAgentOption> cursorSandboxOptions = <ManagedAgentOption>[
  ManagedAgentOption('enabled', 'Enabled'),
  ManagedAgentOption('disabled', 'Disabled'),
];

const List<ManagedAgentOption> agyModeOptions = <ManagedAgentOption>[
  ManagedAgentOption('accept-edits', 'Accept Edits'),
  ManagedAgentOption('plan', 'Plan'),
];

const List<ManagedAgentOption> piThinkingOptions = <ManagedAgentOption>[
  ManagedAgentOption('off', 'Off'),
  ManagedAgentOption('minimal', 'Minimal'),
  ManagedAgentOption('low', 'Low'),
  ManagedAgentOption('medium', 'Medium'),
  ManagedAgentOption('high', 'High'),
  ManagedAgentOption('xhigh', 'Extra High'),
  ManagedAgentOption('max', 'Max'),
];

const List<ManagedAgentOption> piTrustOptions = <ManagedAgentOption>[
  ManagedAgentOption('approve', 'Approve'),
  ManagedAgentOption('ignore', 'Ignore'),
];

const List<ManagedAgentOption> ampModeOptions = <ManagedAgentOption>[
  ManagedAgentOption('low', 'Low'),
  ManagedAgentOption('medium', 'Medium'),
  ManagedAgentOption('high', 'High'),
  ManagedAgentOption('ultra', 'Ultra'),
];

const List<ManagedAgentOption> grokEffortOptions = <ManagedAgentOption>[
  ManagedAgentOption('none', 'None'),
  ManagedAgentOption('minimal', 'Minimal'),
  ManagedAgentOption('low', 'Low'),
  ManagedAgentOption('medium', 'Medium'),
  ManagedAgentOption('high', 'High'),
  ManagedAgentOption('xhigh', 'Extra High'),
  ManagedAgentOption('max', 'Max'),
];

const List<ManagedAgentOption> grokPermissionOptions = <ManagedAgentOption>[
  ManagedAgentOption('default', 'Default'),
  ManagedAgentOption('acceptEdits', 'Accept Edits'),
  ManagedAgentOption('auto', 'Auto'),
  ManagedAgentOption('dontAsk', 'Do Not Ask'),
  ManagedAgentOption('bypassPermissions', 'Bypass Permissions'),
  ManagedAgentOption('plan', 'Plan'),
];

const List<ManagedAgentOption> grokSandboxOptions = <ManagedAgentOption>[
  ManagedAgentOption('off', 'Off'),
  ManagedAgentOption('workspace', 'Workspace'),
  ManagedAgentOption('devbox', 'Devbox'),
  ManagedAgentOption('read-only', 'Read Only'),
  ManagedAgentOption('strict', 'Strict'),
];

/// The profile switcher a Claude Code profile may launch through. It takes the
/// profile as its first positional argument and forwards the rest to `claude`
/// unchanged. Mirrors `CCS_EXECUTABLE` in the Rust launch builder.
const String ccsExecutable = 'ccs';

bool agentProfileSupportsCcsProfile(AgentType adapter) {
  return adapter == AgentType.claude;
}

bool agentProfileSupportsModel(AgentType adapter) {
  return adapter != AgentType.amp && adapter != AgentType.fx;
}

bool agentProfileSupportsPersona(AgentType adapter) {
  return switch (adapter) {
    AgentType.claude ||
    AgentType.copilot ||
    AgentType.agy ||
    AgentType.opencode ||
    AgentType.opencode2 ||
    AgentType.grok => true,
    _ => false,
  };
}

int managedAgentRiskScore(AgentType adapter, Map<String, Object?> config) {
  var score = 0;
  void addWhen(bool condition, int value) {
    if (condition) {
      score += value;
    }
  }

  switch (adapter) {
    case AgentType.codex:
      addWhen(config['bypassApprovalsAndSandbox'] == true, 100);
      addWhen(config['sandbox'] == 'danger-full-access', 40);
      addWhen(config['approvalPolicy'] == 'never', 30);
    case AgentType.claude:
      addWhen(config['permissionMode'] == 'bypassPermissions', 100);
      addWhen(config['permissionMode'] == 'dontAsk', 40);
      addWhen(config['allowSkipPermissions'] == true, 30);
    case AgentType.copilot:
      addWhen(config['allowAll'] == true, 70);
      addWhen(config['mode'] == 'autopilot', 40);
      addWhen(config['noAskUser'] == true, 30);
    case AgentType.cursor:
      addWhen(config['permissionMode'] == 'force', 70);
      addWhen(config['sandbox'] == 'disabled', 50);
      addWhen(config['trustWorkspace'] == true, 20);
    case AgentType.agy:
      addWhen(config['skipPermissions'] == true, 100);
    case AgentType.opencode:
    case AgentType.opencode2:
      addWhen(config['autoApprove'] == true, 60);
    case AgentType.pi:
      addWhen(config['projectTrust'] == 'approve', 30);
    case AgentType.grok:
      addWhen(config['permissionMode'] == 'bypassPermissions', 100);
      addWhen(config['permissionMode'] == 'dontAsk', 40);
    case AgentType.amp:
    case AgentType.fx:
      break;
  }
  return score;
}

Set<String> managedAgentRiskMarkers(
  AgentType adapter,
  Map<String, Object?> config,
) {
  final markers = <String>{};
  void markWhen(bool condition, String marker) {
    if (condition) {
      markers.add(marker);
    }
  }

  switch (adapter) {
    case AgentType.codex:
      markWhen(
        config['bypassApprovalsAndSandbox'] == true,
        'bypassApprovalsAndSandbox',
      );
      markWhen(config['sandbox'] == 'danger-full-access', 'dangerFullAccess');
      markWhen(config['approvalPolicy'] == 'never', 'neverAsk');
    case AgentType.claude:
      markWhen(
        config['permissionMode'] == 'bypassPermissions',
        'bypassPermissions',
      );
      markWhen(config['permissionMode'] == 'dontAsk', 'dontAsk');
      markWhen(config['allowSkipPermissions'] == true, 'allowSkipPermissions');
    case AgentType.copilot:
      markWhen(config['allowAll'] == true, 'allowAll');
      markWhen(config['mode'] == 'autopilot', 'autopilot');
      markWhen(config['noAskUser'] == true, 'noAskUser');
    case AgentType.cursor:
      markWhen(config['permissionMode'] == 'force', 'force');
      markWhen(config['sandbox'] == 'disabled', 'sandboxDisabled');
      markWhen(config['trustWorkspace'] == true, 'trustWorkspace');
    case AgentType.agy:
      markWhen(config['skipPermissions'] == true, 'skipPermissions');
    case AgentType.opencode:
    case AgentType.opencode2:
      markWhen(config['autoApprove'] == true, 'autoApprove');
    case AgentType.pi:
      markWhen(config['projectTrust'] == 'approve', 'projectTrust');
    case AgentType.grok:
      markWhen(
        config['permissionMode'] == 'bypassPermissions',
        'bypassPermissions',
      );
      markWhen(config['permissionMode'] == 'dontAsk', 'dontAsk');
    case AgentType.amp:
    case AgentType.fx:
      break;
  }
  return markers;
}

String managedAgentRiskWarning(AgentType adapter, Map<String, Object?> config) {
  return switch (adapter) {
    AgentType.codex when config['bypassApprovalsAndSandbox'] == true =>
      'This profile will bypass Codex approvals and sandbox protections.',
    AgentType.codex =>
      'This profile reduces Codex approval or sandbox protections.',
    AgentType.claude =>
      'This profile lets Claude continue with reduced permission prompts.',
    AgentType.copilot =>
      'This profile lets Copilot take broader actions with less supervision.',
    AgentType.cursor =>
      'This profile reduces Cursor review, sandbox, or trust protections.',
    AgentType.agy => 'This profile lets Antigravity skip permission checks.',
    AgentType.opencode || AgentType.opencode2 =>
      'This profile lets OpenCode approve actions automatically.',
    AgentType.pi => 'This profile pre-approves project trust for Pi.',
    AgentType.grok =>
      'This profile lets Grok Build continue with reduced permission prompts.',
    AgentType.amp => '',
    AgentType.fx => '',
  };
}

String managedAgentCommandPreview(
  AgentType adapter,
  Map<String, Object?> config,
) {
  var executable = agentProfileDefaultCommands[adapter] ?? adapter.key;
  final arguments = <String>[];
  void stringOption(String key, String flag) {
    final value = config[key];
    if (value is String && value.trim().isNotEmpty) {
      arguments.addAll(<String>[flag, value.trim()]);
    }
  }

  void flag(String key, String value) {
    if (config[key] == true) {
      arguments.add(value);
    }
  }

  void numberOption(String key, String flag) {
    final value = config[key];
    if (value is num) {
      arguments.addAll(<String>[flag, value.toString()]);
    }
  }

  switch (adapter) {
    case AgentType.codex:
      stringOption('model', '--model');
      final effort = config['effort'];
      if (effort is String && effort.isNotEmpty) {
        arguments.addAll(<String>[
          '--config',
          'model_reasoning_effort=$effort',
        ]);
      }
      final planModeEffort = config['planModeEffort'];
      if (planModeEffort is String && planModeEffort.isNotEmpty) {
        arguments.addAll(<String>[
          '--config',
          'plan_mode_reasoning_effort=$planModeEffort',
        ]);
      }
      if (config['bypassApprovalsAndSandbox'] == true) {
        arguments.add('--dangerously-bypass-approvals-and-sandbox');
      } else {
        stringOption('sandbox', '--sandbox');
        stringOption('approvalPolicy', '--ask-for-approval');
      }
      flag('webSearch', '--search');
    case AgentType.claude:
      final ccsProfile = config['ccsProfile'];
      if (ccsProfile is String && ccsProfile.trim().isNotEmpty) {
        executable = ccsExecutable;
        arguments.add(ccsProfile.trim());
      }
      stringOption('model', '--model');
      stringOption('effort', '--effort');
      stringOption('agent', '--agent');
      stringOption('permissionMode', '--permission-mode');
      flag('allowSkipPermissions', '--allow-dangerously-skip-permissions');
    case AgentType.copilot:
      stringOption('model', '--model');
      stringOption('effort', '--effort');
      stringOption('agent', '--agent');
      stringOption('mode', '--mode');
      stringOption('context', '--context');
      flag('allowAll', '--allow-all');
      numberOption('maxAiCredits', '--max-ai-credits');
      numberOption('maxAutopilotContinues', '--max-autopilot-continues');
      flag('noAskUser', '--no-ask-user');
    case AgentType.cursor:
      stringOption('model', '--model');
      stringOption('mode', '--mode');
      if (config['permissionMode'] == 'autoReview') {
        arguments.add('--auto-review');
      } else if (config['permissionMode'] == 'force') {
        arguments.add('--force');
      }
      stringOption('sandbox', '--sandbox');
      flag('trustWorkspace', '--trust');
    case AgentType.agy:
      stringOption('model', '--model');
      stringOption('effort', '--effort');
      stringOption('agent', '--agent');
      stringOption('mode', '--mode');
      flag('skipPermissions', '--dangerously-skip-permissions');
      flag('sandbox', '--sandbox');
    case AgentType.opencode:
      stringOption('model', '--model');
      stringOption('agent', '--agent');
      flag('autoApprove', '--auto');
    case AgentType.opencode2:
      // Interactive opencode2 only accepts --auto on the default TUI command.
      flag('autoApprove', '--auto');
    case AgentType.pi:
      stringOption('model', '--model');
      stringOption('thinking', '--thinking');
      if (config['projectTrust'] == 'approve') {
        arguments.add('--approve');
      } else if (config['projectTrust'] == 'ignore') {
        arguments.add('--no-approve');
      }
    case AgentType.amp:
      stringOption('mode', '--mode');
      flag('fast', '--fast');
    case AgentType.grok:
      stringOption('model', '--model');
      stringOption('effort', '--effort');
      stringOption('agent', '--agent');
      stringOption('permissionMode', '--permission-mode');
      stringOption('sandbox', '--sandbox');
      flag('disableWebSearch', '--disable-web-search');
    case AgentType.fx:
      flag('resumeLast', '--continue');
      flag('noAdditionalDirs', '--no-additional-dirs');
      flag('record', '--record');
  }
  return <String>[
    executable,
    ...arguments.map(_quotePreviewArgument),
  ].join(' ');
}

String _quotePreviewArgument(String value) {
  if (RegExp(r'^[A-Za-z0-9_./:=+-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}
