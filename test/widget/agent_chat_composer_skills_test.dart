import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/chips/alera_inline_chip.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_message_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_skill_chips.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_skill_text_controller.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const AgentChatComposerSettings _settings = AgentChatComposerSettings(
  provider: 'claudeAgent',
  providerInstanceId: 'claudeAgent',
  session: AgentChatSession(
    status: AgentChatSessionStatus.ready,
    commands: <AgentChatProviderCommand>[
      AgentChatProviderCommand(name: 'compact'),
      AgentChatProviderCommand(name: 'review'),
    ],
  ),
  providers: <AgentChatProviderInstance>[],
  canSwitchProvider: true,
  configuring: false,
);

const List<AgentChatProviderSkill> _skills = <AgentChatProviderSkill>[
  AgentChatProviderSkill(
    name: 'review',
    path: '/s/review/SKILL.md',
    displayName: 'Code Review',
    shortDescription: 'Review the diff',
  ),
  AgentChatProviderSkill(name: 'deploy-app', path: '/s/deploy/SKILL.md'),
  AgentChatProviderSkill(
    name: 'internal',
    path: '/s/internal/SKILL.md',
    userInvocable: false,
  ),
];

final class _Harness {
  _Harness(Future<AgentChatSkillList> Function() answer)
    : skills = AgentChatSkillsLoader(({required refresh}) {
        loads += 1;
        return answer();
      });

  final TerminalComposerController composer = TerminalComposerController(
    textController: AgentChatSkillTextController(),
  );
  final AleraPopoverController picker = AleraPopoverController();
  final AgentChatSkillsLoader skills;
  static int loads = 0;

  TextEditingController get text => composer.textController;

  Widget build() => MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
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
          hintText: 'Message the agent',
          promptHistory: () => const <String>[],
          pickerController: picker,
          skills: skills,
          onSend: (_, _, {steer = false}) => true,
          onInterrupt: () {},
          onConfigure: (_) {},
          onChoose: (_, _) {},
          onOpenFile: (_) {},
        ),
      ),
    ),
  );

  void dispose() {
    composer.dispose();
    picker.dispose();
    skills.dispose();
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  Future<AgentChatSkillList> Function()? answer,
}) async {
  _Harness.loads = 0;
  final harness = _Harness(
    answer ?? () async => const AgentChatSkillList(skills: _skills),
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(harness.build());
  await tester.tap(find.byType(TextField));
  await tester.pump();
  return harness;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.pump();
}

final Finder _menu = find.byKey(
  const ValueKey<String>('agent-chat-composer-menu'),
);

void main() {
  testWidgets(r'$ lists the skills a person can pick and inserts $name', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _type(tester, r'please $');
    expect(_menu, findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Code Review'), findsOneWidget);
    expect(find.text('Review the diff'), findsOneWidget);
    expect(find.text('Deploy App'), findsOneWidget);
    expect(find.text('Internal'), findsNothing);
    expect(_Harness.loads, 1);

    await _type(tester, r'please $dep');
    expect(find.text('Code Review'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(harness.text.text, r'please $deploy-app ');
    expect(_menu, findsNothing);
  });

  testWidgets('amounts never open the skills menu', (tester) async {
    await _pump(tester);
    await _type(tester, r'it costs $5');
    expect(_menu, findsNothing);
  });

  testWidgets('/ lists skills as /skill:name after the commands', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _type(tester, '/');
    await tester.pump();
    expect(find.text('/compact'), findsOneWidget);
    // The skill shadows the agent command of the same name.
    expect(find.text('/review'), findsNothing);
    expect(find.text('/skill:review'), findsOneWidget);
    expect(find.text('/skill:deploy-app'), findsOneWidget);

    await _type(tester, '/skill:rev');
    await tester.tap(find.text('/skill:review'));
    await tester.pump();
    expect(harness.text.text, r'$review ');
  });

  testWidgets('a later / offers skills and local commands only', (
    tester,
  ) async {
    await _pump(tester);
    await _type(tester, 'then /');
    await tester.pump();
    expect(find.text('/model'), findsOneWidget);
    expect(find.text('/compact'), findsNothing);
    expect(find.text('/skill:review'), findsOneWidget);
  });

  testWidgets('an agent that reports skills after it starts says so', (
    tester,
  ) async {
    await _pump(
      tester,
      answer: () async =>
          const AgentChatSkillList(status: AgentChatSkillsStatus.pending),
    );
    await _type(tester, r'$');
    expect(
      find.text('Skills appear once the agent starts. Send a message first.'),
      findsOneWidget,
    );
  });

  testWidgets(r'a runtime without skills leaves $ as text', (tester) async {
    await _pump(
      tester,
      answer: () async =>
          throw const AgentChatCapabilityRequired('agentChatSkillsV1'),
    );
    await _type(tester, r'$');
    await tester.pump();
    expect(_menu, findsNothing);
    await _type(tester, r'$r');
    expect(_menu, findsNothing);
    expect(_Harness.loads, 1);
  });

  test('the composer paints finished mentions of known skills', () {
    final controller = AgentChatSkillTextController(text: r'run $review now')
      ..skills = _skills;
    addTearDown(controller.dispose);
    final span = controller.buildTextSpan(
      context: _FakeContext(),
      withComposing: false,
    );
    final runs = span.children!.cast<TextSpan>();
    expect(runs.map((run) => run.text), <String>['run ', r'$review', ' now']);
    expect(runs[1].style?.backgroundColor, isNotNull);
    expect(runs.first.style, isNull);
  });

  testWidgets('a sent message draws the skills it invoked as chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: AgentChatSkillsScope(
            skills: _skills,
            child: AgentChatUserMessageView(
              chatId: 'chat-1',
              item: AgentChatItem(
                id: 'u1',
                type: AgentChatItemType.userMessage,
                status: AgentChatItemStatus.completed,
                createdAt: DateTime.utc(2026, 10, 26),
                updatedAt: DateTime.utc(2026, 10, 26),
                text: r'$review the diff, €deploy-app next, $unknown stays, $5 too',
              ),
              workspacePath: '/repo',
              onOpenFile: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final chip = find.byType(AleraInlineChip);
    expect(chip, findsNWidgets(2));
    expect(
      find.descendant(of: chip, matching: find.text('Code Review')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chip, matching: find.text('Deploy App')),
      findsOneWidget,
    );
  });
}

final class _FakeContext extends Fake implements BuildContext {}
