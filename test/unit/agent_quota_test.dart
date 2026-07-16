import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quota request key ignores provider and CCS display order', () {
    const first = AgentQuotaHostSettings(
      enabledProviders: <AgentQuotaProviderId>[
        AgentQuotaProviderId.claude,
        AgentQuotaProviderId.antigravity,
      ],
      claudeProfiles: <ClaudeQuotaProfileSettings>[
        ClaudeQuotaProfileSettings(alias: 'cc41', profile: 'leynier41'),
        ClaudeQuotaProfileSettings(alias: 'ccdev', profile: 'leynierdev'),
      ],
    );
    const reordered = AgentQuotaHostSettings(
      enabledProviders: <AgentQuotaProviderId>[
        AgentQuotaProviderId.antigravity,
        AgentQuotaProviderId.claude,
      ],
      claudeProfiles: <ClaudeQuotaProfileSettings>[
        ClaudeQuotaProfileSettings(alias: 'ccdev', profile: 'leynierdev'),
        ClaudeQuotaProfileSettings(alias: 'cc41', profile: 'leynier41'),
      ],
    );

    expect(agentQuotaRequestKey(first), agentQuotaRequestKey(reordered));
  });

  test('parses quota windows and reports the lowest remaining percentage', () {
    final snapshot = AgentQuotaSnapshot.fromJson(<String, Object?>{
      'provider': 'codex',
      'accountId': 'default',
      'displayName': 'Codex',
      'status': 'ok',
      'updatedAt': 1_700_000_000_000,
      'windows': <Object?>[
        <String, Object?>{
          'label': '5 Hour',
          'usedPercent': 20,
          'windowMinutes': 300,
        },
        <String, Object?>{
          'label': 'Weekly',
          'usedPercent': '65',
          'windowMinutes': 10080,
        },
      ],
      'buckets': <Object?>[],
    });

    expect(snapshot.provider, AgentQuotaProviderId.codex);
    expect(snapshot.remainingPercent, 35);
    expect(snapshot.windows.first.remainingPercent, 80);
  });

  test(
    'parses quota buckets and falls back for malformed snapshot metadata',
    () {
      final snapshot = AgentQuotaSnapshot.fromJson(<String, Object?>{
        'provider': 'minimax',
        'status': 'unexpected',
        'buckets': <Object?>[
          <String, Object?>{
            'usedPercent': '25',
            'windowMinutes': 300,
            'resetsAt': 1_700_000_000_000,
            'resetDescription': 'Soon',
          },
        ],
      });

      expect(snapshot.status, AgentQuotaStatus.error);
      expect(
        snapshot.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(snapshot.buckets.single.name, 'Quota');
      expect(snapshot.buckets.single.remainingPercent, 75);
      expect(snapshot.buckets.single.windowMinutes, 300);
      expect(
        snapshot.buckets.single.resetsAt,
        DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000, isUtc: true),
      );
      expect(snapshot.buckets.single.resetDescription, 'Soon');
    },
  );

  test('preserves usage while marking a cached snapshot stale', () {
    final snapshot = AgentQuotaSnapshot.fromJson(<String, Object?>{
      'provider': 'claude',
      'status': 'ok',
      'updatedAt': 1_700_000_000_000,
      'windows': <Object?>[
        <String, Object?>{'label': 'Weekly', 'usedPercent': 40},
      ],
    });

    final stale = snapshot.asStale('Refresh failed');

    expect(stale.status, AgentQuotaStatus.stale);
    expect(stale.remainingPercent, 60);
    expect(stale.error, 'Refresh failed');
  });

  test('finds snapshots by provider and account', () {
    final snapshot = AgentQuotaSnapshot.fromJson(<String, Object?>{
      'provider': 'claude',
      'accountId': 'ccdev',
      'status': 'ok',
    });
    final state = AgentQuotaState(
      hostId: 'local',
      snapshots: <AgentQuotaSnapshot>[snapshot],
      environment: const <String, bool>{},
      fetchedAt: DateTime.utc(2026),
    );

    expect(
      state.snapshot(AgentQuotaProviderId.claude, accountId: 'ccdev'),
      same(snapshot),
    );
    expect(state.snapshot(AgentQuotaProviderId.codex), isNull);
  });
}
