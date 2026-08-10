import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_usage/domain/agent_usage.dart';
import 'package:alera/src/features/agent_usage/presentation/agent_usage_dialog.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders usage, current limits, and CCS account breakdown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _wrap(
        AgentUsageDialogView(
          hostId: 'local',
          days: 30,
          snapshot: _snapshot(),
          quotaSnapshots: <AgentQuotaSnapshot>[
            _quota(
              provider: AgentQuotaProviderId.claude,
              accountId: 'dev',
              displayName: 'ccdev',
              usedPercent: 40,
            ),
            _quota(provider: AgentQuotaProviderId.codex, usedPercent: 20),
          ],
          loading: false,
          error: null,
          onDaysChanged: (_) {},
          onRefresh: () {},
          onClose: () {},
        ),
      ),
    );

    expect(find.text('Usage'), findsOneWidget);
    expect(find.text('Local Host'), findsOneWidget);
    expect(find.text('Current Limits'), findsOneWidget);
    expect(find.text('Claude Code ccdev'), findsOneWidget);
    expect(find.text('40% Used'), findsOneWidget);
    expect(find.text('Processed Tokens'), findsOneWidget);
    expect(find.text('49'), findsOneWidget);
    expect(find.text(r'$1.75'), findsOneWidget);
    expect(find.text('Daily Activity'), findsOneWidget);
    expect(find.text('ccdev'), findsWidgets);
    expect(find.text('Transcript content stays on this host.'), findsNothing);
    expect(
      find.textContaining('Transcript content stays on this host.'),
      findsOneWidget,
    );
  });

  testWidgets('changes range, refreshes, and switches to model breakdown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selectedDays = 30;
    var refreshes = 0;
    await tester.pumpWidget(
      _wrap(
        AgentUsageDialogView(
          hostId: 'remote-dev',
          days: 30,
          snapshot: _snapshot(),
          quotaSnapshots: const <AgentQuotaSnapshot>[],
          loading: false,
          error: null,
          onDaysChanged: (value) => selectedDays = value,
          onRefresh: () => refreshes += 1,
          onClose: () {},
        ),
      ),
    );

    await tester.tap(find.text('7 Days'));
    await tester.pump();
    expect(selectedDays, 7);

    await tester.tap(find.byTooltip('Refresh Usage'));
    expect(refreshes, 1);

    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();
    expect(find.text('claude-opus-5'), findsOneWidget);
    expect(find.text('gpt-5.6-codex'), findsOneWidget);
  });

  testWidgets('shows a retry state when usage is unavailable', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _wrap(
        AgentUsageDialogView(
          hostId: 'local',
          days: 30,
          snapshot: null,
          quotaSnapshots: const <AgentQuotaSnapshot>[],
          loading: false,
          error: 'Runtime does not support usage.',
          onDaysChanged: (_) {},
          onRefresh: () => retries += 1,
          onClose: () {},
        ),
      ),
    );

    expect(find.text('Usage Unavailable'), findsOneWidget);
    expect(find.text('Runtime does not support usage.'), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    expect(retries, 1);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(body: child),
  );
}

AgentUsageSnapshot _snapshot() {
  return AgentUsageSnapshot.fromJson(<String, Object?>{
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
        'distinctSessions': 3,
      },
      <String, Object?>{
        'provider': 'codex',
        'accountId': 'default',
        'displayName': 'Default',
        'status': 'ok',
        'scannedFiles': 1,
        'distinctSessions': 2,
      },
    ],
    'buckets': <Object?>[
      _bucket(
        provider: 'claude',
        accountId: 'dev',
        displayName: 'ccdev',
        model: 'claude-opus-5',
        day: '2026-08-09',
        tokens: 35,
        cost: 1.25,
      ),
      _bucket(
        provider: 'codex',
        accountId: 'default',
        displayName: 'Default',
        model: 'gpt-5.6-codex',
        day: '2026-08-10',
        tokens: 14,
        cost: 0.5,
      ),
    ],
  });
}

Map<String, Object?> _bucket({
  required String provider,
  required String accountId,
  required String displayName,
  required String model,
  required String day,
  required int tokens,
  required double cost,
}) {
  return <String, Object?>{
    'provider': provider,
    'accountId': accountId,
    'displayName': displayName,
    'model': model,
    'day': day,
    'totals': <String, Object?>{
      'uncachedInputTokens': tokens,
      'cachedInputTokens': 0,
      'cacheCreationTokens': 0,
      'outputTokens': 0,
      'reasoningTokens': 0,
    },
    'costUsd': cost,
    'cacheSavingsUsd': 0,
    'costSource': 'modelPriced',
    'records': 1,
    'unpricedRecords': 0,
    'sessions': 1,
  };
}

AgentQuotaSnapshot _quota({
  required AgentQuotaProviderId provider,
  String accountId = 'default',
  String displayName = 'Default',
  required double usedPercent,
}) {
  return AgentQuotaSnapshot(
    provider: provider,
    accountId: accountId,
    displayName: displayName,
    status: AgentQuotaStatus.ok,
    updatedAt: DateTime.utc(2026),
    error: null,
    windows: <AgentQuotaWindow>[
      AgentQuotaWindow(
        label: 'Weekly',
        usedPercent: usedPercent,
        windowMinutes: null,
        resetsAt: null,
        resetDescription: null,
      ),
    ],
    buckets: const <AgentQuotaBucket>[],
  );
}
