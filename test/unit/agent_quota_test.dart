import 'dart:async';

import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_quota/infra/runtime_proxy_client.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_process_runner.dart';

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

  test('does not invalidate the quota provider after disposal', () {
    fakeAsync((async) {
      final container = ProviderContainer(
        overrides: [
          workbenchControllerProvider.overrideWithValue(const WorkbenchState()),
          settingsControllerProvider.overrideWithValue(.defaults),
          sshTargetsProvider.overrideWith(
            (ref) => Stream<List<SshTarget>>.value(const <SshTarget>[]),
          ),
          agentQuotaServiceProvider.overrideWithValue(
            AgentQuotaService(
              RuntimeProxyClient(
                processRunner: FakeRecordingProcessRunner(<Object>[]),
              ),
              _FixedQuotaRuntimeHostClient(<String, Object?>{
                'snapshots': const <Object?>[],
                'environment': const <String, bool>{},
              }),
            ),
          ),
        ],
      );
      final providerSubscription = container.listen(
        agentQuotaStateProvider,
        (_, _) {},
        fireImmediately: true,
      );
      async.flushMicrotasks();
      async.elapse(.zero);
      async.flushMicrotasks();
      expect(container.read(agentQuotaStateProvider).hasValue, isTrue);

      providerSubscription.close();
      container.dispose();
      async.elapse(agentQuotaRefreshInterval);
      async.flushMicrotasks();
    });
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
    expect(snapshot.key, 'codex:default');
    expect(snapshot.pinKey, 'codex');
    expect(snapshot.hasUsage, isTrue);
    expect(snapshot.remainingPercent, 35);
    expect(snapshot.windows.first.remainingPercent, 80);
  });

  test('parses OpenCode estimated windows and spend amounts', () {
    final snapshot = AgentQuotaSnapshot.fromJson(<String, Object?>{
      'provider': 'opencode',
      'accountId': 'zen',
      'status': 'ok',
      'dataQuality': 'estimated',
      'scope': 'host',
      'windows': <Object?>[
        <String, Object?>{
          'label': '5 Hour',
          'usedPercent': 25,
          'spentAmount': '3.50',
          'currency': 'USD',
        },
      ],
      'amounts': <Object?>[
        <String, Object?>{
          'label': 'Local Spend (30d)',
          'currency': 'USD',
          'spentAmount': 12.5,
          'resetsAt': 1_700_000_000_000,
          'resetDescription': 'Host-local estimate',
        },
      ],
    });

    expect(snapshot.provider, AgentQuotaProviderId.opencode);
    expect(snapshot.dataQuality, 'estimated');
    expect(snapshot.scope, 'host');
    expect(snapshot.hasUsage, isTrue);
    expect(snapshot.windows.single.spentAmount, 3.5);
    expect(snapshot.windows.single.currency, 'USD');
    expect(snapshot.amounts.single.spentAmount, 12.5);
    expect(snapshot.amounts.single.resetsAt, isNotNull);
  });

  test('parses Codex reset credits without exposing account identity', () {
    final snapshot = AgentQuotaSnapshot.fromJson(<String, Object?>{
      'provider': 'codex',
      'status': 'ok',
      'rateLimitResetCredits': <String, Object?>{
        'availableCount': 2,
        'totalEarnedCount': 5,
        'nextExpiresAt': 1_900_000_000_000,
        'offerRevision': 'opaque-revision',
        'canConsume': true,
      },
    });

    expect(snapshot.rateLimitResetCredits?.availableCount, 2);
    expect(snapshot.rateLimitResetCredits?.totalEarnedCount, 5);
    expect(
      snapshot.rateLimitResetCredits?.nextExpiresAt,
      DateTime.fromMillisecondsSinceEpoch(1_900_000_000_000, isUtc: true),
    );
    expect(snapshot.rateLimitResetCredits?.offerRevision, 'opaque-revision');
    expect(snapshot.rateLimitResetCredits?.canConsume, isTrue);
  });

  test('defaults malformed Codex reset credit metadata safely', () {
    final credits = CodexResetCredits.fromJson(<String, Object?>{
      'availableCount': -1,
    });

    expect(credits.availableCount, 0);
    expect(credits.totalEarnedCount, isNull);
    expect(credits.nextExpiresAt, isNull);
    expect(credits.offerRevision, isEmpty);
    expect(credits.canConsume, isFalse);
  });

  test('parses a consumed Codex reset response', () {
    final result = CodexResetConsumeResult.fromJson(<String, Object?>{
      'status': 'consumed',
      'outcome': 'reset',
      'reason': 'Reset applied.',
      'snapshot': <String, Object?>{'provider': 'codex', 'status': 'ok'},
    });

    expect(result.status, CodexResetConsumeStatus.consumed);
    expect(result.outcome, CodexResetConsumeOutcome.reset);
    expect(result.reason, 'Reset applied.');
    expect(result.snapshot.provider, AgentQuotaProviderId.codex);
  });

  test('defaults unknown Codex reset response values to rejected', () {
    final result = CodexResetConsumeResult.fromJson(<String, Object?>{
      'status': 'unknown',
      'outcome': 'unknown',
      'snapshot': <String, Object?>{'provider': 'codex', 'status': 'ok'},
    });

    expect(result.status, CodexResetConsumeStatus.rejected);
    expect(result.outcome, isNull);
    expect(result.reason, isNull);
  });

  test('rejects a Codex reset response without a snapshot', () {
    expect(
      () => CodexResetConsumeResult.fromJson(<String, Object?>{
        'status': 'consumed',
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Codex reset response missing snapshot.',
        ),
      ),
    );
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
      fetchedAt: .utc(2026),
    );

    expect(state.snapshot(.claude, accountId: 'ccdev'), same(snapshot));
    expect(state.snapshot(.codex), isNull);
  });

  test('creates an empty quota state at the epoch', () {
    final state = AgentQuotaState.empty('local');

    expect(state.hostId, 'local');
    expect(state.snapshots, isEmpty);
    expect(state.environment, isEmpty);
    expect(
      state.fetchedAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  });

  test('tryFromJson returns null for an unknown provider name', () {
    final snapshot = AgentQuotaSnapshot.tryFromJson(<String, Object?>{
      'provider': 'newprovider',
      'accountId': 'default',
      'status': 'ok',
    });

    expect(snapshot, isNull);
  });

  test('tryFromJson parses known payloads like fromJson', () {
    final payload = <String, Object?>{
      'provider': 'claude',
      'accountId': 'ccdev',
      'displayName': 'Claude Dev',
      'status': 'unexpected',
      'updatedAt': 1_700_000_000_000,
      'error': 'Quota metadata is stale.',
      'windows': <Object?>[
        <String, Object?>{
          'label': 'Weekly',
          'usedPercent': 35,
          'windowMinutes': 10080,
          'resetsAt': 1_700_100_000_000,
          'resetDescription': 'Tomorrow',
        },
      ],
      'buckets': <Object?>[
        <String, Object?>{
          'name': 'Sonnet',
          'usedPercent': 20,
          'windowMinutes': 300,
        },
      ],
    };
    final strict = AgentQuotaSnapshot.fromJson(payload);
    final tolerant = AgentQuotaSnapshot.tryFromJson(payload);

    expect(tolerant, isNotNull);
    expect(tolerant!.provider, strict.provider);
    expect(tolerant.accountId, strict.accountId);
    expect(tolerant.displayName, strict.displayName);
    expect(tolerant.status, strict.status);
    expect(tolerant.updatedAt, strict.updatedAt);
    expect(tolerant.error, strict.error);
    expect(tolerant.windows.single.label, strict.windows.single.label);
    expect(
      tolerant.windows.single.remainingPercent,
      strict.windows.single.remainingPercent,
    );
    expect(tolerant.buckets.single.name, strict.buckets.single.name);
    expect(
      tolerant.buckets.single.remainingPercent,
      strict.buckets.single.remainingPercent,
    );
  });

  test(
    'quota service keeps known snapshots beside unknown providers',
    () async {
      final runtime = _FixedQuotaRuntimeHostClient(<String, Object?>{
        'snapshots': <Object?>[
          <String, Object?>{
            'provider': 'claude',
            'accountId': 'default',
            'displayName': 'Claude Code',
            'status': 'ok',
            'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
          },
          <String, Object?>{
            'provider': 'newprovider',
            'accountId': 'default',
            'status': 'ok',
          },
        ],
        'environment': <String, bool>{'KIMI_API_KEY': true},
      });
      final service = AgentQuotaService(
        RuntimeProxyClient(
          processRunner: FakeRecordingProcessRunner(<Object>[]),
        ),
        runtime,
      );

      final state = await service.fetch(
        hostId: 'local',
        target: null,
        settings: .defaults,
      );

      expect(state.error, isNull);
      expect(state.snapshots, hasLength(1));
      expect(state.snapshots.single.provider, AgentQuotaProviderId.claude);
      expect(state.snapshots.single.status, AgentQuotaStatus.ok);
      expect(state.environment, <String, bool>{'KIMI_API_KEY': true});
    },
  );

  test('quota service accepts payloads with only unknown providers', () async {
    final runtime = _FixedQuotaRuntimeHostClient(<String, Object?>{
      'snapshots': <Object?>[
        <String, Object?>{'provider': 'newprovider', 'status': 'ok'},
      ],
    });
    final service = AgentQuotaService(
      RuntimeProxyClient(processRunner: FakeRecordingProcessRunner(<Object>[])),
      runtime,
    );

    final state = await service.fetch(
      hostId: 'local',
      target: null,
      settings: .defaults,
    );

    expect(state.error, isNull);
    expect(state.snapshots, isEmpty);
  });
}

final class _FixedQuotaRuntimeHostClient(final Map<String, Object?> payload)
    implements RuntimeHostClient {
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    expect(type, 'agentQuota.snapshot');
    return this.payload;
  }
}
