import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_find.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_find_bar.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_action_scope_region.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_shortcuts_scope.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

final Workspace _workspace = Workspace(
  id: 'ws-1',
  projectId: 'project-1',
  name: 'Alera',
  path: '/projects/alera',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  kind: WorkspaceKind.main,
  status: WorkspaceStatus.active,
);

final TargetPlatformVariant _linux = TargetPlatformVariant.only(
  TargetPlatform.linux,
);

class _DefaultSettings extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}

/// [turns] settled turns; the first one ran two commands, so its work folds.
List<Map<String, Object?>> _items(int turns) => <Map<String, Object?>>[
  for (var turn = 0; turn < turns; turn += 1) ...<Map<String, Object?>>[
    agentChatItemFixture(
      'u$turn',
      'user_message',
      turnId: 't$turn',
      text: 'Question $turn',
    ),
    if (turn == 0) ...<Map<String, Object?>>[
      agentChatItemFixture(
        'c1',
        'command_execution',
        turnId: 't0',
        normalized: <String, Object?>{'command': 'ls'},
      ),
      agentChatItemFixture(
        'c2',
        'command_execution',
        turnId: 't0',
        normalized: <String, Object?>{'command': 'cat pubspec.yaml'},
      ),
    ],
    agentChatItemFixture(
      'a$turn',
      'assistant_message',
      turnId: 't$turn',
      text: List<String>.filled(
        4,
        turn == 0 ? 'The needle is here.' : 'Answer line for turn $turn.',
      ).join('\n\n'),
    ),
  ],
];

AgentChatSnapshot _snapshot(
  List<Map<String, Object?>> items, {
  String interactionMode = 'default',
  String? historyBefore,
}) => AgentChatSnapshot.fromJson(<String, Object?>{
  'chatId': 'chat-1',
  'workspaceId': 'ws-1',
  'tabId': 'tab-1',
  'provider': 'codex',
  'providerInstanceId': 'codex',
  'title': 'Find',
  'cursor': 1,
  'historyBefore': ?historyBefore,
  'session': <String, Object?>{
    'status': 'ready',
    'model': 'gpt-5',
    'interactionMode': interactionMode,
    'capabilities': <String, Object?>{'plan': true},
  },
  'turns': <Object?>[
    for (final turnId in <String?>{
      for (final item in items) item['turnId'] as String?,
    })
      if (turnId != null)
        <String, Object?>{
          'turnId': turnId,
          'status': 'completed',
          'startedAt': '2026-10-12T10:00:00Z',
          'completedAt': '2026-10-12T10:00:09Z',
        },
  ],
  'items': items,
  'pendingRequests': <Object?>[],
});

Future<void> _pumpChat(WidgetTester tester, AgentChatSnapshot snapshot) async {
  var nextId = 0;
  final repository = FakeAgentChatRepository()..snapshots.add(() => snapshot);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsControllerProvider.overrideWith(_DefaultSettings.new),
        chatTasksSupportedProvider.overrideWith((ref) async => false),
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: KeyboardShortcutsScope(
            child: KeyboardActionScopeRegion(
              scope: KeyboardActionScope.agentChat,
              target: 'chat-1',
              child: AgentChatSurface(
                chatId: 'chat-1',
                workspace: _workspace,
                fallbackTitle: 'Agent Chat',
                fallbackProvider: 'codex',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

Finder get _composer => find.descendant(
  of: find.byType(AgentChatComposer),
  matching: find.byType(EditableText),
);

Finder get _findField => find.descendant(
  of: find.byKey(const ValueKey<String>('agent-chat-find-field')),
  matching: find.byType(EditableText),
);

Future<void> _pressFind(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

String _count(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey<String>('agent-chat-find-count')))
    .data!;

bool _onScreen(WidgetTester tester, Finder finder) {
  final viewport = tester.getRect(
    find.byKey(const ValueKey<String>('agent-chat-timeline')),
  );
  final rect = tester.getRect(finder);
  return rect.top >= viewport.top && rect.top < viewport.bottom;
}

void main() {
  testWidgets(
    'Ctrl+F in the composer opens find, Escape hands the focus back',
    (tester) async {
      await _pumpChat(tester, _snapshot(_items(3)));
      await tester.tap(_composer);
      await tester.pumpAndSettle();

      await _pressFind(tester);

      expect(
        find.byKey(const ValueKey<String>('agent-chat-find-bar')),
        findsOneWidget,
      );
      expect(
        tester.widget<EditableText>(_findField).focusNode.hasFocus,
        isTrue,
      );
      // The chord opened find rather than typing into the composer.
      expect(tester.widget<EditableText>(_composer).controller.text, isEmpty);

      await tester.enterText(_findField, 'question');
      await tester.pumpAndSettle();
      expect(_count(tester), '1 of 3');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('agent-chat-find-bar')),
        findsNothing,
      );
      expect(tester.widget<EditableText>(_composer).focusNode.hasFocus, isTrue);
    },
    variant: _linux,
  );

  testWidgets('a match in folded work far up opens it and scrolls to it', (
    tester,
  ) async {
    await _pumpChat(tester, _snapshot(_items(30)));
    await tester.tap(_composer);
    await tester.pumpAndSettle();
    await _pressFind(tester);

    await tester.enterText(_findField, 'pubspec');
    await tester.pumpAndSettle();

    expect(_count(tester), '1 of 1');
    final row = find.byKey(
      const ValueKey<String>('agent-chat-find-activity-actions-c1'),
    );
    expect(row, findsOneWidget);
    expect(_onScreen(tester, row), isTrue);
    // The command group opened to show the matching command.
    expect(find.textContaining('cat pubspec.yaml'), findsWidgets);
    final highlight = tester.widget<DecoratedBox>(
      find.descendant(of: row, matching: find.byType(DecoratedBox)).first,
    );
    expect((highlight.decoration as BoxDecoration).border, isNotNull);
  }, variant: _linux);

  testWidgets('Enter and Shift+Enter step through matches and wrap', (
    tester,
  ) async {
    await _pumpChat(tester, _snapshot(_items(20)));
    await tester.tap(_composer);
    await tester.pumpAndSettle();
    await _pressFind(tester);
    await tester.enterText(_findField, 'needle');
    await tester.pumpAndSettle();
    expect(_count(tester), '1 of 1');

    await tester.enterText(_findField, 'question 1');
    await tester.pumpAndSettle();
    // Question 1 and Questions 10 to 19.
    expect(_count(tester), endsWith(' of 11'));
    final start = _count(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_count(tester), isNot(start));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(_count(tester), start);

    await tester.enterText(_findField, 'nowhere');
    await tester.pumpAndSettle();
    expect(_count(tester), 'No results');
  }, variant: _linux);

  testWidgets('says only loaded messages are searched', (tester) async {
    await _pumpChat(tester, _snapshot(_items(2), historyBefore: 'cursor-1'));
    await tester.tap(_composer);
    await tester.pumpAndSettle();
    await _pressFind(tester);

    expect(
      find.byKey(const ValueKey<String>('agent-chat-find-loaded-only')),
      findsOneWidget,
    );
  }, variant: _linux);

  testWidgets('Refine focuses the composer to answer the plan', (tester) async {
    await _pumpChat(
      tester,
      _snapshot(<Map<String, Object?>>[
        agentChatItemFixture('u1', 'user_message', text: 'Plan the change'),
        agentChatItemFixture('p1', 'plan', text: '# Plan\n\n1. Rename it'),
      ], interactionMode: 'plan'),
    );
    expect(find.text('Describe what to change in the plan'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-refine-plan')),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<EditableText>(_composer).focusNode.hasFocus, isTrue);
    expect(
      find.byKey(const ValueKey<String>('agent-chat-implement-plan')),
      findsOneWidget,
    );
  });

  test('the count reads like a person would say it', () {
    final find = AgentChatFindController();
    addTearDown(find.dispose);
    expect(agentChatFindCountLabel(find), isNull);
    find.setQuery('x');
    expect(agentChatFindCountLabel(find), 'No results');
  });
}
