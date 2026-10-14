import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_footer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tab_view.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_turn_view.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

DateTime _now() => DateTime.utc(2026, 10, 12, 10, 0, 8);

Future<FakeAgentChatClient> _pumpChat(
  WidgetTester tester, {
  required double height,
  required double keyboard,
  required double textScale,
  bool pending = true,
  bool supportsTasks = false,
  bool recovery = false,
  bool offline = false,
}) async {
  tester.view.physicalSize = Size(360, height);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  final client = FakeAgentChatClient();
  final snapshot = agentChatSnapshot(
    session: agentChatSession(status: 'waiting', activeTurnId: 'turn-1'),
    turns: <Map<String, Object?>>[
      agentChatTurn('turn-1', status: 'running', completedAt: null),
    ],
    recovery: recovery
        ? <String, Object?>{
            'kind': 'interrupted',
            'message': 'The runtime restarted while the agent was working. Resume the saved session or start a new one.',
            'canResume': true,
            'canRestart': true,
          }
        : null,
    items: <Map<String, Object?>>[
      agentChatItem(
        'prompt',
        type: 'user_message',
        text: 'Review the release.',
      ),
    ],
    pendingRequests: <Map<String, Object?>>[
      if (pending)
        <String, Object?>{
          'requestId': 'question-1',
          'kind': 'tool_user_input',
          'turnId': 'turn-1',
          'questions': <Object?>[
            <String, Object?>{
              'id': 'target',
              'header': 'Validation',
              'question': 'Which environment should receive the release after validation?',
              'multiSelect': true,
              'allowCustomAnswer': true,
              'options': <Object?>[
                <String, Object?>{
                  'label': 'Staging',
                  'description':
                      'Run the migration on the staging database first.',
                },
                <String, Object?>{
                  'label': 'Production',
                  'description':
                      'Release the validated revision to production.',
                },
              ],
            },
          ],
        },
    ],
    queue: <Map<String, Object?>>[
      if (pending)
        <String, Object?>{
          'queueId': 'queue-1',
          'clientMessageId': 'queued-1',
          'text': 'Verify reconnect behavior on the paired phone.',
          'createdAt': '2026-10-12T10:01:00Z',
        },
    ],
  );
  client.handlers['agentChat.snapshot'] = (_) => snapshot;
  client.handlers['agentChat.recover'] = (_) => <String, Object?>{
    'snapshot': <String, Object?>{...snapshot, 'cursor': 4, 'recovery': null},
  };
  client.handlers['agentChat.respond'] = (_) => <String, Object?>{
    'resolved': true,
  };
  client.handlers['agentChat.queueCancel'] = (_) => <String, Object?>{
    'cancelled': true,
  };
  client.handlers['agentChat.send'] = (_) => <String, Object?>{
    'delivery': 'queued',
  };
  final workspace = FakeTerminalClient();
  addTearDown(workspace.dispose);
  addTearDown(client.disconnect);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mobileAgentChatClientProvider('host')
            .overrideWith((ref) async => client),
        workspaceClientProvider('host').overrideWith((ref) async => workspace),
        mobileAiDictationSettingsControllerProvider.overrideWith(
          FakeMobileAiDictationSettingsController.new,
        ),
        mobileChatTasksSupportedProvider('host')
            .overrideWith((ref) async => supportsTasks),
        if (supportsTasks)
          mobileChatTaskListProvider(
            'host',
            const AgentChatTaskQuery(parentChatId: 'chat-1'),
          ).overrideWith((ref) => Stream.value(AgentChatTaskPage.empty)),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: AgentChatElapsedClock(now: _now, child: child!),
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('Agent Chat')),
          body: const AgentChatTabView(
            hostId: 'host',
            workspaceId: 'workspace-1',
            chatId: 'chat-1',
            provider: 'codex',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (offline) {
    client.handlers['agentChat.snapshot'] = (_) =>
        throw const AgentChatConnectionException('The host is not reachable.');
    ProviderScope.containerOf(
      tester.element(find.byType(AgentChatTabView)),
    ).invalidate(agentChatControllerProvider('host', 'workspace-1', 'chat-1'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }
  return client;
}

void _expectPinnedActions(WidgetTester tester, {bool enabled = true}) {
  final body = tester.getRect(find.byType(AgentChatTabView));
  for (final tooltip in <String>['Queue Message', 'Stop']) {
    final action = find.byTooltip(tooltip);
    if (enabled) {
      expect(
        action.hitTestable(),
        findsOneWidget,
        reason: '$tooltip at ${tester.getRect(action)} within $body',
      );
    }
    if (!enabled) {
      final button = find.ancestor(
        of: action,
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(button).onPressed, isNull);
    }
    final rect = tester.getRect(action);
    expect(rect.top, greaterThanOrEqualTo(body.top));
    expect(rect.bottom, lessThanOrEqualTo(body.bottom));
  }
}

void _expectCaretVisible(WidgetTester tester) {
  final composer = find.byType(AgentChatComposer);
  final editable = tester
      .state<EditableTextState>(
        find.descendant(of: composer, matching: find.byType(EditableText)),
      )
      .renderEditable;
  final transform = editable.getTransformTo(null);
  final viewport =
      MatrixUtils.transformRect(
        transform,
        Offset.zero & editable.size,
      ).intersect(
        tester.getRect(
          find.descendant(
            of: composer,
            matching: find.byType(SingleChildScrollView),
          ),
        ),
      );
  final caret = MatrixUtils.transformRect(
    transform,
    editable.getLocalRectForCaret(
      TextPosition(offset: editable.text!.toPlainText().length),
    ),
  );
  expect(
    caret.top,
    greaterThanOrEqualTo(viewport.top),
    reason: '$caret in $viewport',
  );
  expect(
    caret.bottom,
    lessThanOrEqualTo(viewport.bottom),
    reason: '$caret in $viewport',
  );
  expect(
    viewport.contains(caret.center),
    isTrue,
    reason: '$caret in $viewport',
  );
}

void main() {
  setUpAll(() async {
    // Use shipped glyphs so 200% checks measure the app's text geometry.
    for (final entry in <String, String>{
      'Inter': 'Inter-Variable.ttf',
      'JetBrains Mono': 'JetBrainsMono-Variable.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load('assets/fonts/${entry.value}'))).load();
    }
  });
  const scenarios =
      <({String name, double height, double keyboard, double scale})>[
        (name: 'normal viewport', height: 800, keyboard: 0, scale: 1),
        (name: 'short viewport', height: 500, keyboard: 0, scale: 1),
        (name: 'keyboard inset', height: 800, keyboard: 300, scale: 1),
        (name: '200 percent text', height: 500, keyboard: 0, scale: 2),
        (
          name: 'keyboard with 200 percent text',
          height: 800,
          keyboard: 300,
          scale: 2,
        ),
        (
          name: 'short viewport keyboard with 200 percent text',
          height: 500,
          keyboard: 200,
          scale: 2,
        ),
        (
          name: 'high keyboard with 200 percent text',
          height: 500,
          keyboard: 280,
          scale: 2,
        ),
      ];
  for (final scenario in scenarios) {
    testWidgets('question queue and composer stay usable in ${scenario.name}', (
      tester,
    ) async {
      final client = await _pumpChat(
        tester,
        height: scenario.height,
        keyboard: scenario.keyboard,
        textScale: scenario.scale,
      );
      expect(tester.takeException(), isNull);
      final body = find.byType(AgentChatTabView);
      expect(
        tester.getRect(find.byType(AgentChatFooter)).bottom,
        lessThanOrEqualTo(tester.getRect(body).bottom),
      );
      final composerField = find.descendant(
        of: find.byType(AgentChatComposer),
        matching: find.byType(TextField),
      );
      await tester.enterText(
        composerField,
        'Check the release.\nKeep the transcript.\nCheck the paired phone.\nReport the result.',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _expectCaretVisible(tester);
      _expectPinnedActions(tester);
      await tester.tap(find.byTooltip('Queue Message'));
      await tester.pumpAndSettle();
      expect(
        client.payloadsOf('agentChat.send').single['text'],
        contains('Check the paired phone.'),
      );

      final staging = find.text('Staging');
      await tester.ensureVisible(staging);
      await tester.pumpAndSettle();
      await tester.tap(staging);
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Submit');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      expect(submit.hitTestable(), findsOneWidget);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(
        client.payloadsOf('agentChat.respond').single['response'],
        <String, Object?>{
          'type': 'userInput',
          'answers': <String, Object?>{
            'target': <String>['Staging'],
          },
        },
      );

      final remove = find.byTooltip('Remove Queued Message');
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      expect(remove.hitTestable(), findsOneWidget);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(
        client.payloadsOf('agentChat.queueCancel').single['queueId'],
        'queue-1',
      );
      expect(tester.takeException(), isNull);
      _expectPinnedActions(tester);
    });
  }
  testWidgets('empty task docks leave room to edit above pinned controls', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      height: 500,
      keyboard: 280,
      textScale: 2,
      pending: false,
      supportsTasks: true,
    );
    final composer = find.byType(AgentChatComposer);
    await tester.enterText(
      find.descendant(of: composer, matching: find.byType(TextField)),
      'First line.\nSecond line.\nThird line.\nFourth line.',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final inputScroll = find.descendant(
      of: composer,
      matching: find.byType(SingleChildScrollView),
    );
    expect(
      tester.getSize(inputScroll).height,
      greaterThan(tester.getSize(find.byType(AgentChatTabView)).height / 2),
    );
    _expectPinnedActions(tester);
  });
  testWidgets('a working duration fits a narrow turn at 200 percent text', (
    tester,
  ) async {
    final turn = AgentChatTurn.fromJson(
      agentChatTurn('turn-1', status: 'running', completedAt: null),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: AgentChatElapsedClock(
              now: _now,
              child: SizedBox(
                width: 120,
                child: AgentChatTurnView(
                  section: AgentChatTurnSection.fromItems(
                    'turn-1',
                    const <AgentChatItem>[],
                    turn: turn,
                    working: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Working for 8s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final notice in <({String name, bool recovery, bool offline})>[
    (name: 'recovery', recovery: true, offline: false),
    (name: 'offline error', recovery: false, offline: true),
    (name: 'recovery and offline error', recovery: true, offline: true),
  ]) {
    for (final keyboard in <double>[0, 280]) {
      testWidgets(
        '${notice.name} keeps controls visible at 200 percent with keyboard $keyboard',
        (tester) async {
          final client = await _pumpChat(
            tester,
            height: 500,
            keyboard: keyboard,
            textScale: 2,
            recovery: notice.recovery,
            offline: notice.offline,
          );
          final field = find.descendant(
            of: find.byType(AgentChatComposer),
            matching: find.byType(TextField),
          );
          if (notice.offline) {
            expect(tester.widget<TextField>(field).enabled, isFalse);
            final draft =
                'First line.\nSecond line.\nThird line.\nFourth line.';
            tester
                .widget<TextField>(field)
                .controller!
                .value = TextEditingValue(
              text: draft,
              selection: TextSelection.collapsed(offset: draft.length),
            );
            await tester.pump();
            await tester.pump();
          } else {
            await tester.enterText(
              field,
              'First line.\nSecond line.\nThird line.\nFourth line.',
            );
            await tester.pumpAndSettle();
            _expectCaretVisible(tester);
          }
          expect(tester.takeException(), isNull);
          _expectPinnedActions(tester, enabled: !notice.offline);
          final action = find.widgetWithText(
            TextButton,
            notice.offline ? 'Retry' : 'Resume Session',
          );
          await tester.ensureVisible(action);
          await tester.pump();
          expect(action.hitTestable(), findsOneWidget);
          if (!notice.offline) {
            await tester.tap(action);
            await tester.pumpAndSettle();
            expect(
              client.payloadsOf('agentChat.recover').single['mode'],
              'resume',
            );
            expect(find.byType(SnackBar), findsNothing);
          }
          expect(tester.takeException(), isNull);
          _expectPinnedActions(tester, enabled: !notice.offline);
        },
      );
    }
  }
}
