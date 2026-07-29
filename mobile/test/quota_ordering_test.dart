import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_snapshot.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orders snapshots by enabled providers and Claude profiles', () {
    final settings = QuotaSettings(
      enabledProviders: const <String>['minimax', 'claude'],
      claudeDefaultEnabled: true,
      claudeProfiles: const <ClaudeQuotaProfile>[
        ClaudeQuotaProfile(alias: 'Partsbase', profile: 'partsbase'),
      ],
      environment: const QuotaEnvironment(),
    );
    final ordered = sortedQuotaSnapshots(<QuotaSnapshot>[
      _snapshot(provider: 'claude', accountId: 'partsbase', name: 'Partsbase'),
      _snapshot(provider: 'minimax', accountId: 'default', name: 'MiniMax'),
      _snapshot(provider: 'claude', accountId: 'default', name: 'Default'),
    ], settings: settings);

    expect(
      ordered.map((item) => '${item.provider}:${item.accountId}').toList(),
      <String>['minimax:default', 'claude:default', 'claude:partsbase'],
    );
  });

  test('orders Claude meters as 5H then weekly then Fable', () {
    final meters = sortedQuotaMeters(
      QuotaSnapshot(
        provider: 'claude',
        accountId: 'default',
        displayName: 'Default',
        status: 'ok',
        updatedAt: DateTime.utc(2026),
        error: null,
        windows: const <QuotaMeter>[
          QuotaMeter(
            label: 'Weekly',
            usedPercent: 40,
            resetsAt: null,
            resetDescription: null,
          ),
          QuotaMeter(
            label: 'Fable',
            usedPercent: 10,
            resetsAt: null,
            resetDescription: null,
          ),
          QuotaMeter(
            label: '5 Hour',
            usedPercent: 20,
            resetsAt: null,
            resetDescription: null,
          ),
        ],
        buckets: const <QuotaMeter>[],
      ),
    );

    expect(meters.map((meter) => meter.label).toList(), <String>[
      '5 Hour',
      'Weekly',
      'Fable',
    ]);
  });

  test('parses Codex reset credits', () {
    final snapshot = QuotaSnapshot.fromJson(<String, Object?>{
      'provider': 'codex',
      'status': 'ok',
      'rateLimitResetCredits': <String, Object?>{
        'availableCount': 1,
        'nextExpiresAt': 1_900_000_000_000,
        'offerRevision': 'opaque-revision',
        'canConsume': true,
      },
    });

    expect(snapshot.rateLimitResetCredits?.availableCount, 1);
    expect(snapshot.rateLimitResetCredits?.offerRevision, 'opaque-revision');
    expect(snapshot.rateLimitResetCredits?.canConsume, isTrue);
  });
}

QuotaSnapshot _snapshot({
  required String provider,
  required String accountId,
  required String name,
}) {
  return QuotaSnapshot(
    provider: provider,
    accountId: accountId,
    displayName: name,
    status: 'ok',
    updatedAt: DateTime.utc(2026),
    error: null,
    windows: const <QuotaMeter>[],
    buckets: const <QuotaMeter>[],
  );
}
