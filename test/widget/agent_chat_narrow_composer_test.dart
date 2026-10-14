import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const AgentChatSession _session = AgentChatSession(
  status: AgentChatSessionStatus.ready,
  model: 'gpt-6.1-sol',
  capabilities: AgentChatCapabilities(plan: true),
);

const AgentChatComposerSettings _settings = AgentChatComposerSettings(
  provider: 'codex',
  providerInstanceId: 'codex',
  session: _session,
  providers: <AgentChatProviderInstance>[
    AgentChatProviderInstance(
      id: 'codex',
      provider: 'codex',
      label: 'QA Codex',
      runtimeModes: <AgentChatRuntimeMode>[
        AgentChatRuntimeMode.approvalRequired,
        AgentChatRuntimeMode.fullAccess,
      ],
      interactionModes: <AgentChatInteractionMode>[
        AgentChatInteractionMode.standard,
        AgentChatInteractionMode.plan,
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
final Finder _picker = find.byKey(
  const ValueKey<String>('agent-chat-model-picker'),
);
final Finder _more = find.byKey(
  const ValueKey<String>('agent-chat-more-controls'),
);
final Finder _dictation = find.byKey(
  const ValueKey<String>('agent-chat-dictation'),
);

void main() {
  testWidgets(
    'a narrow composer folds its settings and keeps the picker and send',
    (tester) async {
      final composer = TerminalComposerController();
      addTearDown(composer.dispose);
      final sent = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              // About the width of a split right pane in the QA capture.
              child: SizedBox(
                width: 360,
                child: AgentChatComposer(
                  controller: composer,
                  workspaceId: 'ws-1',
                  chatId: 'chat-1',
                  settings: _settings,
                  usage: const AgentChatUsage(),
                  canSend: true,
                  busy: false,
                  canInterrupt: false,
                  interrupting: false,
                  hintText: 'Ask QA Codex anything',
                  promptHistory: () => const <String>[],
                  onSend: (text, _, {steer = false}) {
                    sent.add(text);
                    return true;
                  },
                  onInterrupt: () {},
                  onConfigure: (_) {},
                  onChoose: (_, _) {},
                  onOpenFile: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Approvals and Plan fold into one overflow; the picker stays.
      expect(_picker, findsOneWidget);
      expect(_more, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('agent-chat-plan-toggle')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('agent-chat-runtime-mode-chip')),
        findsNothing,
      );

      // Nothing needs a horizontal scroll at this width.
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: _scroll, matching: find.byType(Scrollable)),
          )
          .position;
      expect(position.maxScrollExtent, 0);

      final viewport = tester.getRect(_scroll);
      expect(
        tester.getRect(_dictation).left - viewport.right,
        greaterThanOrEqualTo(AleraTokens.space8),
      );
      final composerRect = tester.getRect(find.byType(AgentChatComposer));
      final sendRect = tester.getRect(_send);
      expect(sendRect.right, lessThanOrEqualTo(composerRect.right));
      expect(sendRect.left, greaterThanOrEqualTo(viewport.right));
      expect(tester.getRect(_picker).right, lessThanOrEqualTo(viewport.right));

      await tester.enterText(find.byType(TextField), 'Run the tests');
      await tester.pump();
      await tester.tap(_send);
      await tester.pump();
      expect(sent, <String>['Run the tests']);
      expect(tester.takeException(), isNull);
    },
  );
}
