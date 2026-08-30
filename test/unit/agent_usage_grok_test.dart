import 'package:alera/src/features/agent_usage/application/agent_usage_profile_selection.dart';
import 'package:alera/src/features/agent_usage/domain/agent_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Grok stays separate from Codex in totals and every breakdown', () {
    final snapshot = AgentUsageSnapshot.fromJson(<String, Object?>{
      'sinceDay': '2026-08-09',
      'untilDay': '2026-08-10',
      'sources': <Object?>[
        <String, Object?>{
          'provider': 'grok',
          'accountId': 'default',
          'displayName': 'Default',
          'status': 'ok',
          'distinctSessions': 1,
        },
        <String, Object?>{
          'provider': 'codex',
          'accountId': 'default',
          'status': 'ok',
          'distinctSessions': 1,
        },
      ],
      'buckets': <Object?>[
        _bucket('grok', 'grok-4.5-build', 10, 0.75),
        _bucket('grok', 'grok-composer', 20, 0.25),
        _bucket('codex', 'gpt-5.6-codex', 40, 2),
      ],
    });

    expect(snapshot.sources.first.provider, AgentUsageProvider.grok);
    expect(snapshot.buckets.first.provider, AgentUsageProvider.grok);
    expect(snapshot.costUsd, 3);
    expect(snapshot.totals.totalTokens, 70);
    expect(snapshot.sessions, 2);
    final grok = snapshot.providers.singleWhere(
      (row) => row.provider == AgentUsageProvider.grok,
    );
    expect(grok.label, 'Grok Build');
    expect(grok.tokens, 30);
    expect(grok.costUsd, 1);
    expect(grok.sessions, 1);
    expect(grok.records, 2);
    expect(
      snapshot.accounts.map((row) => row.label),
      unorderedEquals(<String>['Grok Build', 'Codex']),
    );
    expect(
      snapshot.models.where((row) => row.provider == AgentUsageProvider.grok),
      hasLength(2),
    );
    expect(snapshot.days.first.grokTokens, 0);
    expect(snapshot.days.last.grokTokens, 30);
    expect(snapshot.days.last.codexTokens, 40);
    expect(snapshot.days.last.claudeTokens, 0);
    expect(snapshot.days.last.tokens, 70);
    expect(snapshot.days.last.costUsd, 3);

    final filtered = snapshot.withClaudeProfileSelection(
      defaultEnabled: false,
      profileLabels: const <String, String>{},
    );
    expect(filtered.totals.totalTokens, 70);
    expect(filtered.sources.first.provider, AgentUsageProvider.grok);
  });

  test('snapshots from older hosts keep working without Grok data', () {
    final snapshot = AgentUsageSnapshot.fromJson(<String, Object?>{
      'sinceDay': '2026-08-10',
      'untilDay': '2026-08-10',
      'buckets': <Object?>[_bucket('codex', 'gpt-5.6-codex', 40, 2)],
    });
    expect(snapshot.days.single.grokTokens, 0);
    expect(snapshot.days.single.tokens, 40);
    expect(snapshot.providers.single.provider, AgentUsageProvider.codex);
  });
}

Map<String, Object?> _bucket(
  String provider,
  String model,
  int tokens,
  double cost,
) => <String, Object?>{
  'provider': provider,
  'model': model,
  'day': '2026-08-10',
  'totals': <String, Object?>{'uncachedInputTokens': tokens},
  'costUsd': cost,
  'costSource': 'providerReported',
  'records': 1,
  'sessions': 1,
};
