import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_status_bar.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Agent Quotas', group: 'Status Bar')
Widget agentQuotaStatusBarPreview() => SizedBox(
  width: 1100,
  child: AgentQuotaStatusBarView(
    hostId: 'local',
    settings: const AgentQuotaHostSettings(
      claudeProfiles: <ClaudeQuotaProfileSettings>[
        ClaudeQuotaProfileSettings(alias: 'Partsbase', profile: 'partsbase'),
        ClaudeQuotaProfileSettings(alias: 'ccdev', profile: 'leynierdev'),
        ClaudeQuotaProfileSettings(alias: 'cceducup', profile: 'educup'),
      ],
    ),
    snapshots: _previewSnapshots(),
    onRefresh: () {},
    onTogglePinned: (_, _) {},
  ),
);

@AleraPreview(name: 'Agent Quotas - Unpinned', group: 'Status Bar')
Widget agentQuotaStatusBarUnpinnedPreview() => SizedBox(
  width: 1100,
  child: AgentQuotaStatusBarView(
    hostId: 'local',
    settings: const AgentQuotaHostSettings(
      claudeProfiles: <ClaudeQuotaProfileSettings>[
        ClaudeQuotaProfileSettings(alias: 'Partsbase', profile: 'partsbase'),
        ClaudeQuotaProfileSettings(alias: 'ccdev', profile: 'leynierdev'),
        ClaudeQuotaProfileSettings(alias: 'cceducup', profile: 'educup'),
      ],
      unpinnedQuotaKeys: <String>[
        'claude:educup',
        'kimi',
        'grok',
        'cursor',
        'antigravity',
        'minimax',
        'zai',
      ],
    ),
    snapshots: _previewSnapshots(),
    onRefresh: () {},
    onTogglePinned: (_, _) {},
  ),
);

List<AgentQuotaSnapshot> _previewSnapshots() => <AgentQuotaSnapshot>[
  _claudeSnapshot(),
  _claudeUnavailableSnapshot(),
  _claudeProfileSnapshot('leynierdev', 'ccdev', 34),
  _claudeProfileSnapshot('educup', 'cceducup', 61),
  _snapshot(AgentQuotaProviderId.codex, 'Codex', 43),
  _snapshot(AgentQuotaProviderId.kimi, 'Kimi', 8),
  _snapshot(AgentQuotaProviderId.grok, 'Grok Build', 72),
  _snapshot(AgentQuotaProviderId.cursor, 'Cursor', 14),
  _antigravitySnapshot(),
  _snapshot(AgentQuotaProviderId.minimax, 'MiniMax', 56),
  _snapshot(AgentQuotaProviderId.zai, 'Z.ai', 11),
];

AgentQuotaSnapshot _claudeUnavailableSnapshot() {
  return AgentQuotaSnapshot(
    provider: AgentQuotaProviderId.claude,
    accountId: 'partsbase',
    displayName: 'Partsbase',
    status: AgentQuotaStatus.unavailable,
    updatedAt: DateTime.now().toUtc(),
    error: 'Claude OAuth usage is unavailable',
    windows: const <AgentQuotaWindow>[],
    buckets: const <AgentQuotaBucket>[],
  );
}

AgentQuotaSnapshot _claudeSnapshot() {
  return AgentQuotaSnapshot(
    provider: AgentQuotaProviderId.claude,
    accountId: 'default',
    displayName: 'Default',
    status: AgentQuotaStatus.ok,
    updatedAt: DateTime.now().toUtc(),
    error: null,
    windows: <AgentQuotaWindow>[_window('5 Hour', 22), _window('Weekly', 48)],
    buckets: const <AgentQuotaBucket>[
      AgentQuotaBucket(
        name: 'Fable Weekly',
        usedPercent: 31,
        windowMinutes: 10080,
        resetsAt: null,
        resetDescription: 'Resets in 3 days',
      ),
    ],
  );
}

AgentQuotaSnapshot _claudeProfileSnapshot(
  String accountId,
  String displayName,
  double usedPercent,
) {
  return AgentQuotaSnapshot(
    provider: AgentQuotaProviderId.claude,
    accountId: accountId,
    displayName: displayName,
    status: AgentQuotaStatus.ok,
    updatedAt: DateTime.now().toUtc(),
    error: null,
    windows: <AgentQuotaWindow>[
      _window('5 Hour', usedPercent),
      _window('Weekly', usedPercent + 8),
    ],
    buckets: const <AgentQuotaBucket>[],
  );
}

AgentQuotaSnapshot _antigravitySnapshot() {
  return AgentQuotaSnapshot(
    provider: AgentQuotaProviderId.antigravity,
    accountId: 'default',
    displayName: 'Antigravity',
    status: AgentQuotaStatus.ok,
    updatedAt: DateTime.now().toUtc(),
    error: null,
    windows: const <AgentQuotaWindow>[],
    buckets: const <AgentQuotaBucket>[
      AgentQuotaBucket(
        name: 'Gemini Models - 5 Hour',
        usedPercent: 4,
        windowMinutes: 300,
        resetsAt: null,
        resetDescription: null,
      ),
      AgentQuotaBucket(
        name: 'Gemini Models - Weekly',
        usedPercent: 18,
        windowMinutes: 10080,
        resetsAt: null,
        resetDescription: null,
      ),
      AgentQuotaBucket(
        name: 'Claude And GPT Models - 5 Hour',
        usedPercent: 12,
        windowMinutes: 300,
        resetsAt: null,
        resetDescription: null,
      ),
      AgentQuotaBucket(
        name: 'Claude And GPT Models - Weekly',
        usedPercent: 37,
        windowMinutes: 10080,
        resetsAt: null,
        resetDescription: null,
      ),
    ],
  );
}

AgentQuotaSnapshot _snapshot(
  AgentQuotaProviderId provider,
  String displayName,
  double usedPercent,
) {
  return AgentQuotaSnapshot(
    provider: provider,
    accountId: 'default',
    displayName: displayName,
    status: AgentQuotaStatus.ok,
    updatedAt: DateTime.now().toUtc(),
    error: null,
    windows: <AgentQuotaWindow>[_window('Weekly', usedPercent)],
    buckets: const <AgentQuotaBucket>[],
  );
}

AgentQuotaWindow _window(String label, double usedPercent) {
  return AgentQuotaWindow(
    label: label,
    usedPercent: usedPercent,
    windowMinutes: label == '5 Hour' ? 300 : 10080,
    resetsAt: null,
    resetDescription: 'Resets in 3 days',
  );
}
