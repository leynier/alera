import 'package:alera/src/features/agent_usage/domain/agent_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses usage and derives account, model, and daily totals', () {
    final snapshot = AgentUsageSnapshot.fromJson(<String, Object?>{
      'readAt': 1_800_000_000_000,
      'sinceDay': '2026-08-01',
      'untilDay': '2026-08-10',
      'scanDurationMs': 42,
      'pricing': <String, Object?>{
        'status': 'fresh',
        'source': 'rates',
        'knownModels': 10,
      },
      'sources': <Object?>[
        <String, Object?>{
          'provider': 'claude',
          'accountId': 'dev',
          'displayName': 'ccdev',
          'status': 'ok',
          'scannedFiles': 2,
          'skippedFiles': 1,
          'distinctSessions': 3,
        },
        <String, Object?>{
          'provider': 'codex',
          'accountId': 'default',
          'displayName': 'Default',
          'status': 'partial',
          'scannedFiles': 1,
          'distinctSessions': 2,
          'message': 'One file changed during the scan.',
        },
      ],
      'buckets': <Object?>[
        _bucket(
          provider: 'claude',
          accountId: 'dev',
          displayName: 'ccdev',
          model: 'claude-opus-5',
          day: '2026-08-09',
          input: 10,
          cached: 20,
          output: 5,
          cost: 1.25,
          savings: 0.75,
          records: 2,
        ),
        _bucket(
          provider: 'codex',
          accountId: 'default',
          displayName: 'Default',
          model: 'gpt-5.6-codex',
          day: '2026-08-10',
          input: 7,
          cached: 3,
          output: 4,
          cost: 0.5,
          savings: 0.25,
          records: 1,
        ),
      ],
    });

    expect(snapshot.totals.totalTokens, 49);
    expect(snapshot.costUsd, 1.75);
    expect(snapshot.cacheSavingsUsd, 1);
    expect(snapshot.sessions, 5);
    expect(snapshot.records, 3);
    expect(snapshot.accounts, hasLength(2));
    expect(snapshot.accounts.first.label, 'ccdev');
    expect(snapshot.accounts.first.sessions, 3);
    expect(snapshot.models, hasLength(2));
    expect(snapshot.days, hasLength(10));
    expect(snapshot.days.first.day, '2026-08-01');
    expect(snapshot.days.first.tokens, 0);
    expect(
      snapshot.days.singleWhere((day) => day.day == '2026-08-09').claudeTokens,
      35,
    );
    expect(snapshot.days.last.codexTokens, 14);
    expect(snapshot.sources.last.status, AgentUsageSourceStatus.partial);
  });

  test('defaults malformed numeric and enum fields safely', () {
    final snapshot = AgentUsageSnapshot.fromJson(<String, Object?>{
      'readAt': -1,
      'pricing': <String, Object?>{'status': 'future'},
      'sources': <Object?>[
        <String, Object?>{'provider': 'future', 'status': 'future'},
      ],
      'buckets': <Object?>[
        <String, Object?>{
          'provider': 'future',
          'costUsd': -2,
          'costSource': 'future',
          'totals': <String, Object?>{'inputTokens': -1},
        },
      ],
    });

    expect(snapshot.readAt.millisecondsSinceEpoch, 0);
    expect(snapshot.pricing.status, AgentUsagePricingStatus.unavailable);
    expect(snapshot.sources.single.status, AgentUsageSourceStatus.failed);
    expect(snapshot.buckets.single.provider, AgentUsageProvider.codex);
    expect(snapshot.buckets.single.costSource, AgentUsageCostSource.unpriced);
    expect(snapshot.totals.totalTokens, 0);
    expect(snapshot.costUsd, 0);
    expect(snapshot.days.single.day, '');
  });

  test('token totals do not count reasoning twice', () {
    const totals = AgentUsageTokenTotals(
      uncachedInputTokens: 10,
      cachedInputTokens: 20,
      cacheCreationTokens: 5,
      outputTokens: 7,
      reasoningTokens: 3,
    );

    expect(totals.totalTokens, 42);
    expect(totals.totalInputTokens, 35);
  });
}

Map<String, Object?> _bucket({
  required String provider,
  required String accountId,
  required String displayName,
  required String model,
  required String day,
  required int input,
  required int cached,
  required int output,
  required double cost,
  required double savings,
  required int records,
}) {
  return <String, Object?>{
    'provider': provider,
    'accountId': accountId,
    'displayName': displayName,
    'model': model,
    'day': day,
    'totals': <String, Object?>{
      'uncachedInputTokens': input,
      'cachedInputTokens': cached,
      'cacheCreationTokens': 0,
      'outputTokens': output,
      'reasoningTokens': 1,
    },
    'costUsd': cost,
    'cacheSavingsUsd': savings,
    'costSource': 'modelPriced',
    'records': records,
    'unpricedRecords': 0,
    'sessions': 1,
  };
}
