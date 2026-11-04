import 'dart:convert';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_model_picker.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The composer's width in the right panel of the Mac QA capture, with the
/// Chat Actions button beside Add Files.
const double _composerWidth = 254;
const double _chatActionsWidth = 30;

AgentChatComposerSettings _settings({
  String? model,
  AgentChatRuntimeMode runtimeMode = AgentChatRuntimeMode.approvalRequired,
  AgentChatInteractionMode interactionMode = AgentChatInteractionMode.standard,
}) => AgentChatComposerSettings(
  provider: 'codex',
  providerInstanceId: 'codex',
  session: AgentChatSession(
    status: AgentChatSessionStatus.ready,
    model: model,
    runtimeMode: runtimeMode,
    interactionMode: interactionMode,
    capabilities: const AgentChatCapabilities(plan: true),
  ),
  providers: const <AgentChatProviderInstance>[
    AgentChatProviderInstance(
      id: 'codex',
      provider: 'codex',
      label: 'Codex',
      runtimeModes: <AgentChatRuntimeMode>[
        AgentChatRuntimeMode.approvalRequired,
        AgentChatRuntimeMode.fullAccess,
      ],
      interactionModes: <AgentChatInteractionMode>[
        AgentChatInteractionMode.standard,
        AgentChatInteractionMode.plan,
      ],
      models: <AgentChatModelOption>[
        AgentChatModelOption(id: 'gpt-6-sol', label: 'GPT-6-Sol'),
      ],
    ),
  ],
  canSwitchProvider: true,
  configuring: false,
);

final Finder _scroll = find.byKey(
  const ValueKey<String>('agent-chat-composer-controls-scroll'),
);
final Finder _send = find.byKey(const ValueKey<String>('agent-chat-send'));
final Finder _stop = find.byKey(const ValueKey<String>('agent-chat-stop'));
final Finder _picker = find.byKey(
  const ValueKey<String>('agent-chat-model-picker'),
);
final Finder _more = find.byKey(
  const ValueKey<String>('agent-chat-more-controls'),
);
final Finder _fullAccess = find.byKey(
  const ValueKey<String>('agent-chat-full-access-indicator'),
);
final Finder _plan = find.byKey(
  const ValueKey<String>('agent-chat-plan-indicator'),
);

Future<List<AgentChatConfiguration>> _pump(
  WidgetTester tester,
  AgentChatComposerSettings settings, {
  bool busy = false,
}) async {
  final composer = TerminalComposerController();
  addTearDown(composer.dispose);
  final configured = <AgentChatConfiguration>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: _composerWidth,
            child: AgentChatComposer(
              controller: composer,
              workspaceId: 'ws-1',
              chatId: 'chat-1',
              settings: settings,
              usage: const AgentChatUsage(),
              canSend: true,
              busy: busy,
              canInterrupt: false,
              interrupting: false,
              hintText: 'Ask Codex anything',
              promptHistory: () => const <String>[],
              onSend: (_, _, {steer = false}) => true,
              onInterrupt: () {},
              onConfigure: configured.add,
              onChoose: (_, _) {},
              onOpenFile: (_) {},
              chatActions: const SizedBox(width: _chatActionsWidth),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return configured;
}

/// The controls fit the strip without scrolling, every listed control is
/// inside it, and Send or Stop stays inside the composer.
void _expectVisible(WidgetTester tester, Iterable<Finder> controls) {
  final position = tester
      .state<ScrollableState>(
        find.descendant(of: _scroll, matching: find.byType(Scrollable)),
      )
      .position;
  expect(position.maxScrollExtent, 0);
  final strip = tester.getRect(_scroll);
  for (final control in controls) {
    final rect = tester.getRect(control);
    expect(rect.left, greaterThanOrEqualTo(strip.left));
    expect(rect.right, lessThanOrEqualTo(strip.right));
  }
  final composer = tester.getRect(find.byType(AgentChatComposer));
  // A running turn without a draft offers Stop where Send was.
  final send = _send.evaluate().isEmpty ? _stop : _send;
  expect(tester.getRect(send).right, lessThanOrEqualTo(composer.right));
}

String _chipLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: _picker, matching: find.byType(Text)).first,
    )
    .data!;

void main() {
  // Real Inter metrics, since what fits is the point of these tests.
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  testWidgets('the default modes show the plain overflow and the default', (
    tester,
  ) async {
    await _pump(tester, _settings());
    expect(_fullAccess, findsNothing);
    expect(_plan, findsNothing);
    expect(_chipLabel(tester), agentChatCompactProviderDefaultLabel);
    expect(
      find.byTooltip('$agentChatProviderDefaultLabel · Choose Model'),
      findsOneWidget,
    );
    _expectVisible(tester, <Finder>[_picker, _more]);
  });

  testWidgets('Full Access and Plan Mode stay visible at panel width', (
    tester,
  ) async {
    final configured = await _pump(
      tester,
      _settings(
        runtimeMode: AgentChatRuntimeMode.fullAccess,
        interactionMode: AgentChatInteractionMode.plan,
      ),
    );
    _expectVisible(tester, <Finder>[_picker, _more, _fullAccess, _plan]);
    expect(
      find.byTooltip('Full Access · Plan Mode · More Composer Controls'),
      findsOneWidget,
    );

    await tester.tap(_more);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan Mode'));
    await tester.pumpAndSettle();
    expect(
      configured.single.interactionMode,
      AgentChatInteractionMode.standard,
    );
  });

  testWidgets('a running turn keeps Full Access visible but fixed', (
    tester,
  ) async {
    final configured = await _pump(
      tester,
      _settings(runtimeMode: AgentChatRuntimeMode.fullAccess),
      busy: true,
    );
    _expectVisible(tester, <Finder>[_more, _fullAccess]);
    expect(_plan, findsNothing);

    await tester.tap(_more);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(agentChatRuntimeModeLabel(.approvalRequired)),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(configured, isEmpty);
  });

  testWidgets('a long model label ellipsizes before the modes move', (
    tester,
  ) async {
    await _pump(
      tester,
      _settings(
        model: 'gpt-6-sol-extended-context-preview',
        runtimeMode: AgentChatRuntimeMode.fullAccess,
      ),
    );
    expect(_chipLabel(tester), 'gpt-6-sol-extended-context-preview');
    _expectVisible(tester, <Finder>[_picker, _more, _fullAccess]);
  });
}
