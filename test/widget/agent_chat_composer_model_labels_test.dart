import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_model_picker.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final List<AgentChatModelOption> _codexModels = <AgentChatModelOption>[
  const AgentChatModelOption(id: 'gpt-6-sol', label: 'GPT-6-Sol'),
  const AgentChatModelOption(id: 'gpt-6-luna-2026', label: 'GPT-6-Luna'),
  for (var i = 0; i < 12; i++)
    AgentChatModelOption(id: 'gpt-5-$i', label: 'GPT 5 $i'),
];

AgentChatComposerSettings _settings({
  String? model,
  List<AgentChatModelOption>? models,
}) => AgentChatComposerSettings(
  provider: 'codex',
  providerInstanceId: 'codex',
  session: AgentChatSession(status: AgentChatSessionStatus.ready, model: model),
  providers: <AgentChatProviderInstance>[
    AgentChatProviderInstance(
      id: 'codex',
      provider: 'codex',
      label: 'Codex',
      models: models ?? _codexModels,
    ),
  ],
  canSwitchProvider: true,
  configuring: false,
  neverSent: true,
);

final Finder _picker = find.byKey(
  const ValueKey<String>('agent-chat-model-picker'),
);

Future<List<(AgentChatSelection, String)>> _pump(
  WidgetTester tester,
  AgentChatComposerSettings settings,
) async {
  final chosen = <(AgentChatSelection, String)>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(
            width: 280,
            child: AgentChatComposerControls(
              settings: settings,
              enabled: true,
              onChoose: (pick, label) => chosen.add((pick, label)),
              onConfigure: (_) {},
              onOpenProviderSettings: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return chosen;
}

Text _chipText(WidgetTester tester) => tester.widget<Text>(
  find.descendant(of: _picker, matching: find.byType(Text)).first,
);

void main() {
  group('agentChatModelSubtitle', () {
    String? subtitle(String? id, String label) =>
        agentChatModelSubtitle(AgentChatModelOption(id: id, label: label));

    test('hides an id that only restyles the label', () {
      expect(subtitle('gpt-6-sol', 'GPT-6-Sol'), isNull);
      expect(subtitle('gpt-5', 'GPT 5'), isNull);
      expect(subtitle('gpt-5-5', 'GPT-5.5'), isNull);
      expect(subtitle('opus', 'Opus'), isNull);
    });

    test('keeps an id that says something the label does not', () {
      expect(subtitle('gpt-55', 'GPT-5.5'), 'gpt-55');
      expect(
        subtitle('claude-opus-4-1-20250805', 'Claude Opus 4.1'),
        'claude-opus-4-1-20250805',
      );
      expect(subtitle('---', '...'), '---');
      expect(subtitle(null, 'Provider Default'), isNull);
    });
  });

  testWidgets('a chat without a model names the provider default', (
    tester,
  ) async {
    await _pump(tester, _settings());
    expect(_chipText(tester).data, agentChatProviderDefaultLabel);
  });

  testWidgets('the runtime label of the default row wins over the fallback', (
    tester,
  ) async {
    await _pump(
      tester,
      _settings(
        models: const <AgentChatModelOption>[
          AgentChatModelOption(id: null, label: 'Codex Config Default'),
          AgentChatModelOption(id: 'gpt-6-sol', label: 'GPT-6-Sol'),
        ],
      ),
    );
    expect(_chipText(tester).data, 'Codex Config Default');
  });

  testWidgets('a chosen model keeps its own label', (tester) async {
    await _pump(tester, _settings(model: 'gpt-6-sol'));
    expect(_chipText(tester).data, 'GPT-6-Sol');
  });

  testWidgets('an unlisted model shows its id rather than a guess', (
    tester,
  ) async {
    await _pump(tester, _settings(model: 'gpt-7-preview'));
    expect(_chipText(tester).data, 'gpt-7-preview');
  });

  testWidgets('the picker opens on the selected default below the fold', (
    tester,
  ) async {
    await _pump(tester, _settings());
    await tester.tap(_picker);
    await tester.pumpAndSettle();
    final list = tester.getRect(find.byType(ListView));
    final row = tester.getRect(find.text(agentChatProviderDefaultLabel).last);
    expect(row.top, greaterThanOrEqualTo(list.top));
    expect(row.bottom, lessThanOrEqualTo(list.bottom));
  });

  testWidgets('a restyled id is hidden from the row but still found', (
    tester,
  ) async {
    await _pump(tester, _settings(model: 'gpt-6-sol'));
    await tester.tap(_picker);
    await tester.pumpAndSettle();
    expect(find.text('gpt-6-sol'), findsNothing);
    // An id that adds a date stays visible under its label.
    expect(find.text('gpt-6-luna-2026'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gpt-6-sol');
    await tester.pump();
    expect(find.text('GPT-6-Sol'), findsWidgets);
    expect(find.text('GPT-6-Luna'), findsNothing);
  });

  testWidgets('picking the default reports it by name', (tester) async {
    final chosen = await _pump(tester, _settings(model: 'gpt-6-sol'));
    await tester.tap(_picker);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'default');
    await tester.pump();
    await tester.tap(find.text(agentChatProviderDefaultLabel));
    await tester.pumpAndSettle();
    expect(chosen.single.$1.model, isNull);
    expect(chosen.single.$2, agentChatProviderDefaultLabel);
  });
}
