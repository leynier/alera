import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_provider_icon.dart';
import 'package:alera/src/features/agent_usage/domain/agent_usage.dart';
import 'package:alera/src/features/agent_usage/presentation/agent_usage_dialog.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows Grok in metrics, chart, tooltip, and model breakdown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _wrap(
        AgentUsageDialogView(
          hostId: 'local',
          days: 30,
          snapshot: _snapshot(includeGrok: true),
          loading: false,
          error: null,
          onDaysChanged: (_) {},
          onRefresh: () {},
          onClose: () {},
        ),
      ),
    );
    expect(find.text('149'), findsOneWidget);
    expect(find.text(r'$2.75'), findsOneWidget);
    expect(find.text('Grok Build'), findsWidgets);
    expect(
      tester
          .widgetList<AgentQuotaProviderIcon>(
            find.byType(AgentQuotaProviderIcon),
          )
          .where((icon) => icon.provider == AgentQuotaProviderId.grok),
      hasLength(1),
    );
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    final group = chart.data.barGroups.last;
    expect(group.barRods, hasLength(3));
    expect(group.barRods[2].toY, 100);
    expect(chart.data.barGroups.first.barRods[2].color, Colors.transparent);
    final tooltip = chart.data.barTouchData.touchTooltipData.getTooltipItem(
      group,
      chart.data.barGroups.length - 1,
      group.barRods[2],
      2,
    );
    expect(tooltip?.text, contains('Grok Build: 100'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    expect(find.text('grok-4.5-build'), findsOneWidget);
  });

  testWidgets('renders usage metrics and CCS account breakdown', (
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
    expect(find.text('Current Limits'), findsNothing);
    expect(find.text('ccdev'), findsOneWidget);
    expect(find.text('Codex Codex'), findsNothing);
    expect(find.text('Codex'), findsWidgets);
    final cacheSavingsDetail = tester.widget<Text>(
      find.text('Compared with full input rates'),
    );
    expect(cacheSavingsDetail.maxLines, isNull);
    expect(cacheSavingsDetail.overflow, isNull);
    expect(find.text('Processed Tokens'), findsOneWidget);
    expect(find.text('49'), findsOneWidget);
    expect(find.text(r'$1.75'), findsOneWidget);
    expect(find.text('Daily Activity'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    expect(chart.data.barGroups.first.barRods.first.color, Colors.transparent);
    expect(find.text('Transcript content stays on this host.'), findsNothing);
    expect(
      find.textContaining('Transcript content stays on this host.'),
      findsOneWidget,
    );

    final firstMetric = tester.getRect(
      find.byKey(const ValueKey<String>('usage-metric-processed-tokens')),
    );
    final lastMetric = tester.getRect(
      find.byKey(const ValueKey<String>('usage-metric-cache-savings')),
    );
    expect(firstMetric.left, closeTo(140, 0.1));
    expect(lastMetric.right, closeTo(1140, 0.1));
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

    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    expect(find.text('claude-opus-5'), findsOneWidget);
    expect(find.text('gpt-5.6-codex'), findsOneWidget);
  });

  testWidgets('groups selected Claude profiles into one provider row', (
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
          loading: false,
          error: null,
          onDaysChanged: (_) {},
          onRefresh: () {},
          onClose: () {},
        ),
      ),
    );

    await tester.tap(find.text('Grouped'));
    await tester.pumpAndSettle();

    final breakdownPanel = find.byType(AleraPanel).last;
    expect(
      find.descendant(of: breakdownPanel, matching: find.text('Claude Code')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: breakdownPanel, matching: find.text('Codex')),
      findsOneWidget,
    );
  });

  testWidgets('hides Grouped when only one Claude account is in Usage', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _wrap(
        AgentUsageDialogView(
          hostId: 'local',
          days: 7,
          snapshot: _snapshot(),
          showGroupedBreakdown: false,
          loading: false,
          error: null,
          onDaysChanged: (_) {},
          onRefresh: () {},
          onClose: () {},
        ),
      ),
    );

    expect(find.text('Profiles'), findsOneWidget);
    expect(find.text('Grouped'), findsNothing);
    expect(find.text('Models'), findsOneWidget);
  });

  testWidgets('shows a retry state when usage is unavailable', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _wrap(
        AgentUsageDialogView(
          hostId: 'local',
          days: 30,
          snapshot: null,
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

  testWidgets('keeps saved usage visible while refreshing in background', (
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
          loading: true,
          error: null,
          onDaysChanged: (_) {},
          onRefresh: () {},
          onClose: () {},
        ),
      ),
    );

    expect(find.text('Processed Tokens'), findsOneWidget);
    expect(find.text('Updating'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('keeps saved usage visible after a refresh failure', (
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
          loading: false,
          error: 'Runtime is unavailable.',
          onDaysChanged: (_) {},
          onRefresh: () {},
          onClose: () {},
        ),
      ),
    );

    expect(find.text('Processed Tokens'), findsOneWidget);
    expect(find.text('Update Failed'), findsOneWidget);
    expect(find.text('Usage Unavailable'), findsNothing);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(body: child),
  );
}

AgentUsageSnapshot _snapshot({bool includeGrok = false}) {
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
      if (includeGrok)
        <String, Object?>{
          'provider': 'grok',
          'accountId': 'default',
          'displayName': 'Default',
          'status': 'ok',
          'scannedFiles': 1,
          'distinctSessions': 1,
        },
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
      if (includeGrok)
        _bucket(
          provider: 'grok',
          accountId: 'default',
          displayName: 'Default',
          model: 'grok-4.5-build',
          day: '2026-08-10',
          tokens: 100,
          cost: 1,
        ),
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
