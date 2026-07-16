import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_hover_card.dart';
import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_provider_icon.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_status_bar.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows all Claude profiles and Antigravity quotas at a glance', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        settings: const AgentQuotaHostSettings(
          enabledProviders: <AgentQuotaProviderId>[
            AgentQuotaProviderId.claude,
            AgentQuotaProviderId.antigravity,
          ],
          claudeProfiles: <ClaudeQuotaProfileSettings>[
            ClaudeQuotaProfileSettings(alias: 'cc41', profile: 'sonnet41'),
            ClaudeQuotaProfileSettings(alias: 'ccdev', profile: 'dev'),
          ],
        ),
        snapshots: <AgentQuotaSnapshot>[
          _snapshot(
            provider: AgentQuotaProviderId.claude,
            accountId: 'dev',
            displayName: 'ignored-dev-label',
            windows: <AgentQuotaWindow>[_window('Weekly', 55)],
          ),
          _snapshot(
            provider: AgentQuotaProviderId.claude,
            windows: <AgentQuotaWindow>[
              _window('5 Hour', 20),
              _window('Weekly', 40),
            ],
            buckets: <AgentQuotaBucket>[_bucket('Fable Weekly', 30)],
          ),
          _snapshot(
            provider: AgentQuotaProviderId.claude,
            accountId: 'sonnet41',
            displayName: 'ignored-41-label',
            windows: <AgentQuotaWindow>[_window('Weekly', 50)],
          ),
          _snapshot(
            provider: AgentQuotaProviderId.antigravity,
            buckets: <AgentQuotaBucket>[
              _bucket('Gemini Models - 5 Hour', 10),
              _bucket(
                'Gemini Models - Weekly',
                15,
                resetDescription: 'Refreshes in 101h 35m',
              ),
              _bucket('Claude And Gpt Models — 5 Hour', 25),
              _bucket('Claude And Gpt Models — Weekly', 35),
            ],
          ),
        ],
      ),
    );

    expect(find.text('5H'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('G·5H'), findsOneWidget);
    expect(find.text('G·W'), findsOneWidget);
    expect(find.text('C/G·5H'), findsOneWidget);
    expect(find.text('C/G·W'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('cc41'), findsOneWidget);
    expect(find.text('ccdev'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Default')).dx,
      lessThan(tester.getCenter(find.text('cc41')).dx),
    );
    expect(
      tester.getCenter(find.text('cc41')).dx,
      lessThan(tester.getCenter(find.text('ccdev')).dx),
    );
    expect(find.byType(AgentQuotaProviderIcon), findsNWidgets(4));
    expect(find.byType(PopupMenuButton), findsNothing);
    expect(find.text('Claude Code'), findsNothing);
    expect(find.text('Antigravity'), findsNothing);
    expect(find.byType(AleraHoverCard), findsNWidgets(4));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('G·W')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Antigravity'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Gemini Models - Weekly'), findsOneWidget);
    expect(find.text('85% Left'), findsOneWidget);
    expect(find.text('Resets In 4d 5h 35m'), findsOneWidget);
    expect(
      tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .map((indicator) => indicator.value),
      containsAll(<double>[0.9, 0.85, 0.75, 0.65]),
    );
    expect(
      tester.getTopLeft(find.text('Antigravity')).dy,
      lessThan(tester.getTopLeft(find.text('G·W')).dy),
    );
    expect(
      tester
          .widgetList<MouseRegion>(find.byType(MouseRegion))
          .where((region) => region.cursor == SystemMouseCursors.click),
      isNotEmpty,
    );

    await mouse.moveTo(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Antigravity'), findsNothing);
  });

  testWidgets('places refresh after the last agent and rotates while loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        loading: true,
        snapshots: <AgentQuotaSnapshot>[
          _snapshot(
            provider: AgentQuotaProviderId.claude,
            windows: <AgentQuotaWindow>[_window('Weekly', 40)],
          ),
        ],
      ),
    );

    final refresh = find.byTooltip('Refreshing Quotas');
    final host = find.byIcon(AleraIcons.host);
    expect(refresh, findsOneWidget);
    expect(
      tester.getCenter(refresh).dx,
      greaterThan(tester.getCenter(host).dx),
    );
    expect(
      tester.getCenter(refresh).dx,
      greaterThan(tester.getCenter(find.text('60%')).dx),
    );

    final rotation = find.descendant(
      of: refresh,
      matching: find.byType(RotationTransition),
    );
    final before = tester.widget<RotationTransition>(rotation).turns.value;
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<RotationTransition>(rotation).turns.value,
      isNot(before),
    );
    expect(find.text('60%'), findsOneWidget);
  });

  testWidgets('can hide Claude Default while keeping CCS profiles', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        settings: const AgentQuotaHostSettings(
          enabledProviders: <AgentQuotaProviderId>[AgentQuotaProviderId.claude],
          claudeDefaultEnabled: false,
          claudeProfiles: <ClaudeQuotaProfileSettings>[
            ClaudeQuotaProfileSettings(alias: 'ccdev', profile: 'dev'),
          ],
        ),
        snapshots: <AgentQuotaSnapshot>[
          _snapshot(
            provider: AgentQuotaProviderId.claude,
            windows: <AgentQuotaWindow>[_window('Weekly', 40)],
          ),
          _snapshot(
            provider: AgentQuotaProviderId.claude,
            accountId: 'dev',
            displayName: 'ignored-dev-label',
            windows: <AgentQuotaWindow>[_window('Weekly', 20)],
          ),
        ],
      ),
    );

    expect(find.text('Default'), findsNothing);
    expect(find.text('ccdev'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('60%'), findsNothing);
  });

  testWidgets('uses the configured provider display order', (tester) async {
    await tester.pumpWidget(
      _wrap(
        settings: const AgentQuotaHostSettings(
          enabledProviders: <AgentQuotaProviderId>[
            AgentQuotaProviderId.antigravity,
            AgentQuotaProviderId.claude,
          ],
        ),
        snapshots: <AgentQuotaSnapshot>[
          _snapshot(
            provider: AgentQuotaProviderId.claude,
            windows: <AgentQuotaWindow>[_window('Weekly', 40)],
          ),
          _snapshot(
            provider: AgentQuotaProviderId.antigravity,
            buckets: <AgentQuotaBucket>[_bucket('Gemini Models - Weekly', 15)],
          ),
        ],
      ),
    );

    expect(
      tester.getCenter(find.text('G·W')).dx,
      lessThan(tester.getCenter(find.text('Default')).dx),
    );
  });

  testWidgets('capitalizes MiniMax model names in the hover card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        settings: const AgentQuotaHostSettings(
          enabledProviders: <AgentQuotaProviderId>[
            AgentQuotaProviderId.minimax,
          ],
        ),
        snapshots: <AgentQuotaSnapshot>[
          _snapshot(
            provider: AgentQuotaProviderId.minimax,
            displayName: 'MiniMax',
            buckets: <AgentQuotaBucket>[_bucket('general Weekly', 0)],
          ),
        ],
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    expect(find.text('G·W'), findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.text('G·W')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('General Weekly'), findsOneWidget);
  });

  test('refreshes quotas automatically every five minutes', () {
    expect(agentQuotaRefreshInterval, const Duration(minutes: 5));
  });
}

Widget _wrap({
  required List<AgentQuotaSnapshot> snapshots,
  bool loading = false,
  AgentQuotaHostSettings settings = const AgentQuotaHostSettings(
    enabledProviders: <AgentQuotaProviderId>[
      AgentQuotaProviderId.claude,
      AgentQuotaProviderId.antigravity,
    ],
  ),
}) {
  return MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: AgentQuotaStatusBarView(
          hostId: 'local',
          snapshots: snapshots,
          settings: settings,
          loading: loading,
          onRefresh: () {},
        ),
      ),
    ),
  );
}

AgentQuotaSnapshot _snapshot({
  required AgentQuotaProviderId provider,
  String accountId = 'default',
  String displayName = 'Default',
  List<AgentQuotaWindow> windows = const <AgentQuotaWindow>[],
  List<AgentQuotaBucket> buckets = const <AgentQuotaBucket>[],
}) {
  return AgentQuotaSnapshot(
    provider: provider,
    accountId: accountId,
    displayName: displayName,
    status: AgentQuotaStatus.ok,
    updatedAt: DateTime.utc(2026),
    error: null,
    windows: windows,
    buckets: buckets,
  );
}

AgentQuotaWindow _window(String label, double usedPercent) {
  return AgentQuotaWindow(
    label: label,
    usedPercent: usedPercent,
    windowMinutes: null,
    resetsAt: null,
    resetDescription: null,
  );
}

AgentQuotaBucket _bucket(
  String name,
  double usedPercent, {
  String? resetDescription,
}) {
  return AgentQuotaBucket(
    name: name,
    usedPercent: usedPercent,
    windowMinutes: null,
    resetsAt: null,
    resetDescription: resetDescription,
  );
}
