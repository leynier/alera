import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_status_bar.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hides unpinned quotas from the bar while keeping pinned ones', (
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
            ClaudeQuotaProfileSettings(alias: 'ccdev', profile: 'dev'),
          ],
          unpinnedQuotaKeys: <String>['claude:dev', 'antigravity'],
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
          _snapshot(
            provider: AgentQuotaProviderId.antigravity,
            buckets: <AgentQuotaBucket>[_bucket('Gemini Models - Weekly', 15)],
          ),
        ],
      ),
    );

    expect(find.text('Default'), findsOneWidget);
    expect(find.text('ccdev'), findsNothing);
    expect(find.text('G·W'), findsNothing);
    expect(find.text('No Quota Data'), findsNothing);
  });

  testWidgets('opens the overview panel listing pinned and unpinned quotas', (
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
            ClaudeQuotaProfileSettings(alias: 'ccdev', profile: 'dev'),
          ],
          unpinnedQuotaKeys: <String>['claude:dev'],
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
          _snapshot(
            provider: AgentQuotaProviderId.antigravity,
            buckets: <AgentQuotaBucket>[_bucket('Gemini Models - Weekly', 15)],
          ),
        ],
      ),
    );

    // Unpinned quota is absent from the bar until the panel opens.
    expect(find.text('80%'), findsNothing);

    // The overview button sits to the left of every quota summary.
    expect(
      tester.getCenter(find.byIcon(AleraIcons.quota)).dx,
      lessThan(tester.getCenter(find.text('Default')).dx),
    );

    await tester.tap(
      find.byIcon(AleraIcons.quota),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(find.text('Claude Code Default'), findsOneWidget);
    expect(find.text('Claude Code ccdev'), findsOneWidget);
    expect(find.text('Antigravity'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.byIcon(AleraIcons.pin), findsNWidgets(2));
    expect(find.byIcon(AleraIcons.pinOff), findsOneWidget);
    expect(find.byTooltip('Unpin From Status Bar'), findsNWidgets(2));
    expect(find.byTooltip('Pin To Status Bar'), findsOneWidget);
  });

  testWidgets('pin buttons report the toggled key and value', (tester) async {
    final toggles = <(String, bool)>[];
    await tester.pumpWidget(
      _wrap(
        settings: const AgentQuotaHostSettings(
          enabledProviders: <AgentQuotaProviderId>[
            AgentQuotaProviderId.claude,
            AgentQuotaProviderId.antigravity,
          ],
          unpinnedQuotaKeys: <String>['antigravity'],
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
        onTogglePinned: (pinKey, pinned) => toggles.add((pinKey, pinned)),
      ),
    );

    await tester.tap(
      find.byIcon(AleraIcons.quota),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Unpin From Status Bar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pin To Status Bar'));
    await tester.pumpAndSettle();

    expect(toggles, <(String, bool)>[
      ('claude:default', false),
      ('antigravity', true),
    ]);
  });

  testWidgets('renders error quotas with a placeholder reading', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        settings: const AgentQuotaHostSettings(
          enabledProviders: <AgentQuotaProviderId>[AgentQuotaProviderId.codex],
        ),
        snapshots: <AgentQuotaSnapshot>[
          _snapshot(
            provider: AgentQuotaProviderId.codex,
            displayName: 'Codex',
            status: AgentQuotaStatus.error,
            error: 'Request Failed',
          ),
        ],
      ),
    );

    await tester.tap(
      find.byIcon(AleraIcons.quota),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(find.text('Codex'), findsOneWidget);
    // One dash in the bar summary and one in the panel row.
    expect(find.text('-'), findsNWidgets(2));
  });

  testWidgets('open panel reflects pin toggles immediately', (tester) async {
    var settings = const AgentQuotaHostSettings(
      enabledProviders: <AgentQuotaProviderId>[
        AgentQuotaProviderId.claude,
        AgentQuotaProviderId.antigravity,
      ],
    );
    final snapshots = <AgentQuotaSnapshot>[
      _snapshot(
        provider: AgentQuotaProviderId.claude,
        windows: <AgentQuotaWindow>[_window('Weekly', 40)],
      ),
      _snapshot(
        provider: AgentQuotaProviderId.antigravity,
        buckets: <AgentQuotaBucket>[_bucket('Gemini Models - Weekly', 15)],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Align(
              alignment: Alignment.bottomCenter,
              child: AgentQuotaStatusBarView(
                hostId: 'local',
                snapshots: snapshots,
                settings: settings,
                onRefresh: () {},
                onTogglePinned: (pinKey, pinned) => setState(() {
                  final keys = <String>{...settings.unpinnedQuotaKeys};
                  pinned ? keys.remove(pinKey) : keys.add(pinKey);
                  settings = settings.copyWith(
                    unpinnedQuotaKeys: keys.toList(),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('G·W'), findsOneWidget);

    await tester.tap(
      find.byIcon(AleraIcons.quota),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    // One reading in the bar and one in the panel row.
    expect(find.text('G·W'), findsNWidgets(2));
    expect(find.byIcon(AleraIcons.pin), findsNWidgets(2));

    // Unpin Antigravity: the bar item disappears and the row's icon flips
    // while the panel stays open.
    await tester.tap(find.byTooltip('Unpin From Status Bar').last);
    await tester.pumpAndSettle();

    expect(find.text('G·W'), findsOneWidget);
    expect(find.byIcon(AleraIcons.pin), findsOneWidget);
    expect(find.byIcon(AleraIcons.pinOff), findsOneWidget);
    expect(find.text('Antigravity'), findsOneWidget);

    await tester.tap(find.byTooltip('Pin To Status Bar'));
    await tester.pumpAndSettle();
    expect(find.text('G·W'), findsNWidgets(2));
    expect(find.byIcon(AleraIcons.pinOff), findsNothing);
  });

  testWidgets('collapsed narrow bar opens the same overview panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        width: 400,
        settings: const AgentQuotaHostSettings(
          enabledProviders: <AgentQuotaProviderId>[
            AgentQuotaProviderId.claude,
            AgentQuotaProviderId.antigravity,
          ],
          unpinnedQuotaKeys: <String>['antigravity'],
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

    expect(find.text('2 Agent Quotas - Local'), findsOneWidget);

    await tester.tap(
      find.text('2 Agent Quotas - Local'),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(find.text('Claude Code Default'), findsOneWidget);
    expect(find.text('Antigravity'), findsOneWidget);
    expect(find.byTooltip('Unpin From Status Bar'), findsOneWidget);
    expect(find.byTooltip('Pin To Status Bar'), findsOneWidget);
  });
}

Widget _wrap({
  required List<AgentQuotaSnapshot> snapshots,
  required AgentQuotaHostSettings settings,
  AgentQuotaPinToggle? onTogglePinned,
  double width = 1100,
}) {
  return MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: width,
          child: AgentQuotaStatusBarView(
            hostId: 'local',
            snapshots: snapshots,
            settings: settings,
            onRefresh: () {},
            onTogglePinned: onTogglePinned ?? (_, _) {},
          ),
        ),
      ),
    ),
  );
}

AgentQuotaSnapshot _snapshot({
  required AgentQuotaProviderId provider,
  String accountId = 'default',
  String displayName = 'Default',
  AgentQuotaStatus status = AgentQuotaStatus.ok,
  String? error,
  List<AgentQuotaWindow> windows = const <AgentQuotaWindow>[],
  List<AgentQuotaBucket> buckets = const <AgentQuotaBucket>[],
}) {
  return AgentQuotaSnapshot(
    provider: provider,
    accountId: accountId,
    displayName: displayName,
    status: status,
    updatedAt: DateTime.utc(2026),
    error: error,
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

AgentQuotaBucket _bucket(String name, double usedPercent) {
  return AgentQuotaBucket(
    name: name,
    usedPercent: usedPercent,
    windowMinutes: null,
    resetsAt: null,
    resetDescription: null,
  );
}
