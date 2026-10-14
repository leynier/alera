import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_model_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';

final List<AgentChatProviderInstance> _providers = agentChatProvidersFromJson(
  <String, Object?>{
    'providers': <Object?>[
      agentChatProviderRow(
        'codex',
        label: 'Codex',
        models: <Map<String, Object?>>[
          for (var index = 1; index <= 12; index++)
            <String, Object?>{'id': 'gpt-$index', 'label': 'GPT-$index'},
        ],
      ),
      agentChatProviderRow(
        'claudeAgent',
        label: 'Claude',
        models: <Map<String, Object?>>[
          <String, Object?>{'id': 'opus', 'label': 'Opus'},
        ],
      ),
    ],
  },
);

/// Opens the picker on a phone of [size] and returns what it picked.
Future<List<AgentChatSelection?>> _openPicker(
  WidgetTester tester, {
  Size size = const Size(360, 640),
  double textScale = 1,
  double keyboard = 0,
  double homeIndicator = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.view.padding = FakeViewPadding(top: 24, bottom: homeIndicator);
  tester.view.viewPadding = FakeViewPadding(top: 24, bottom: homeIndicator);
  addTearDown(tester.view.reset);
  final picked = <AgentChatSelection?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraMobileDarkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked.add(
              await showAgentChatModelPicker(
                context,
                providers: _providers,
                preferences: const AgentChatPreferences(),
                current: const AgentChatSelection(
                  providerInstanceId: 'codex',
                  model: 'gpt-1',
                ),
                canSwitchProvider: true,
                onOpenProviderSettings: () {},
              ),
            ),
            child: const Text('Pick'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Pick'));
  await tester.pumpAndSettle();
  return picked;
}

Finder get _search => find.descendant(
  of: find.byType(AgentChatModelPickerPanel),
  matching: find.byType(TextField),
);

Finder get _footer => find.text(agentChatOpenProviderSettingsLabel);

double _visibleBottom(WidgetTester tester) =>
    tester.view.physicalSize.height - tester.view.viewInsets.bottom;

void main() {
  testWidgets('a narrowed search stays above the keyboard and picks', (
    tester,
  ) async {
    final picked = await _openPicker(tester);
    await tester.tap(_search);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.enterText(_search, 'opus');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final keyboardTop = _visibleBottom(tester);
    expect(tester.getRect(_search).bottom, lessThanOrEqualTo(keyboardTop));
    expect(tester.getRect(_footer).bottom, lessThanOrEqualTo(keyboardTop));
    final opus = find.byKey(const ValueKey<String>('picker-claudeAgent-opus'));
    expect(tester.getRect(opus).bottom, lessThanOrEqualTo(keyboardTop));

    await tester.tap(opus);
    await tester.pumpAndSettle();
    expect(picked.single?.providerInstanceId, 'claudeAgent');
    expect(picked.single?.model, 'opus');
  });

  testWidgets('a short phone at 200% text scrolls the list over the keys', (
    tester,
  ) async {
    final picked = await _openPicker(
      tester,
      size: const Size(320, 568),
      textScale: 2,
      keyboard: 260,
    );

    expect(tester.takeException(), isNull);
    final keyboardTop = _visibleBottom(tester);
    expect(tester.getRect(_search).bottom, lessThanOrEqualTo(keyboardTop));
    expect(tester.getRect(_footer).bottom, lessThanOrEqualTo(keyboardTop));

    final opus = find.byKey(const ValueKey<String>('picker-claudeAgent-opus'));
    await tester.scrollUntilVisible(
      opus,
      48,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(opus);
    await tester.pumpAndSettle();
    // The row sits in the list's own viewport, between search and footer.
    final row = tester.getRect(opus);
    expect(row.top, greaterThanOrEqualTo(tester.getRect(_search).bottom));
    expect(row.center.dy, lessThan(tester.getRect(_footer).top));
    await tester.tap(opus);
    await tester.pumpAndSettle();
    expect(picked.single?.providerInstanceId, 'claudeAgent');
  });

  testWidgets('the footer clears the home indicator', (tester) async {
    await _openPicker(tester, size: const Size(390, 844), homeIndicator: 34);

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(_footer).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - 34),
    );
  });
}
