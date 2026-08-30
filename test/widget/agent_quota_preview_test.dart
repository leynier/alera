import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_status_bar_content.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quota previews open overlays without native providers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: AgentQuotaStatusBarContent(
            hostId: 'local',
            settings: const AgentQuotaHostSettings(
              enabledProviders: [
                AgentQuotaProviderId.claude,
                AgentQuotaProviderId.codex,
              ],
            ),
            snapshots: [
              for (final provider in [
                AgentQuotaProviderId.claude,
                AgentQuotaProviderId.codex,
              ])
                AgentQuotaSnapshot(
                  provider: provider,
                  accountId: 'default',
                  displayName: 'Default',
                  status: AgentQuotaStatus.unavailable,
                  updatedAt: DateTime.utc(2026),
                  error: 'Preview account is offline',
                  windows: const [],
                  buckets: const [],
                  rateLimitResetCredits: const CodexResetCredits(
                    availableCount: 2,
                    totalEarnedCount: 2,
                    nextExpiresAt: null,
                    offerRevision: 'preview',
                    canConsume: false,
                  ),
                ),
            ],
            onRefresh: () {},
            onTogglePinned: (_, _) {},
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Default')));
    await tester.pump(AleraTokens.durationMid);
    await tester.pumpAndSettle();
    expect(find.text('Try With TUI'), findsNothing);
    expect(tester.takeException(), isNull);

    await mouse.moveTo(const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(AleraIcons.quota));
    await tester.pumpAndSettle();
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Use Reset'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
