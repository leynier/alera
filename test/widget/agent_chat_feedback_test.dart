import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
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

const List<Map<String, Object?>> _codexCommands = <Map<String, Object?>>[
  <String, Object?>{'name': 'compact'},
  <String, Object?>{
    'name': 'feedback',
    'description': 'Send this thread and Codex logs to OpenAI',
  },
];

final class _FeedbackLifecycle extends AgentChatLifecycleRepository {
  _FeedbackLifecycle({this.supported = true});

  final bool supported;
  final List<(String, String, String?)> uploads = <(String, String, String?)>[];
  Completer<String>? answer;

  @override
  Future<bool> supports(String capability) async =>
      supported && capability == AgentChatWire.feedbackCapability;

  @override
  Future<String> feedback(
    AgentChatRef chat, {
    required String requestId,
    String? reason,
  }) {
    uploads.add((chat.chatId, requestId, reason));
    return (answer = Completer<String>()).future;
  }
}

FakeAgentChatRepository _chat({bool sent = true}) =>
    FakeAgentChatRepository()
      ..snapshots.add(
        () => agentChatSnapshotFixture(
          commands: _codexCommands,
          items: sent
              ? <Map<String, Object?>>[
                  agentChatItemFixture('u1', 'user_message', text: 'Fix it'),
                ]
              : const <Map<String, Object?>>[],
          turns: sent
              ? <Map<String, Object?>>[
                  <String, Object?>{
                    'turnId': 'turn-1',
                    'status': 'completed',
                    'startedAt': '2026-10-12T10:00:00Z',
                  },
                ]
              : const <Map<String, Object?>>[],
        ),
      );

Future<void> _pump(
  WidgetTester tester,
  FakeAgentChatRepository repository,
  _FeedbackLifecycle lifecycle,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatLifecycleRepositoryProvider.overrideWithValue(lifecycle),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'fb-1'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: AgentChatSurface(
            chatId: 'chat-1',
            workspace: _workspace,
            fallbackTitle: 'Agent Chat',
            fallbackProvider: 'codex',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder get _field => find.byType(TextField).last;

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(_field).controller!.text;

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('confirming /feedback uploads it and shows the thread id', (
    tester,
  ) async {
    final repository = _chat();
    final lifecycle = _FeedbackLifecycle();
    await _pump(tester, repository, lifecycle);

    await _send(tester, '/feedback The diff was empty');
    expect(find.text(agentChatFeedbackConsentTitle), findsOneWidget);
    expect(find.textContaining('Codex logs to OpenAI'), findsOneWidget);
    expect(lifecycle.uploads, isEmpty);
    expect(_composerText(tester), '/feedback The diff was empty');

    await tester.tap(find.text(agentChatFeedbackConsentConfirmLabel));
    await tester.pump();
    expect(lifecycle.uploads, <(String, String, String?)>[
      ('chat-1', 'fb-1', 'The diff was empty'),
    ]);
    expect(_composerText(tester), isEmpty);
    expect(find.text('Sending feedback to OpenAI...'), findsOneWidget);
    expect(repository.calls.where((call) => call.$1 == 'send'), isEmpty);

    // A second /feedback waits for the one in flight.
    await _send(tester, '/feedback ');
    expect(find.text(agentChatFeedbackConsentTitle), findsNothing);
    expect(lifecycle.uploads, hasLength(1));

    lifecycle.answer!.complete('thread-9');
    await tester.pumpAndSettle();
    expect(
      find.text('Feedback sent to OpenAI\nThread ID: thread-9'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('agent-chat-feedback-dismiss')));
    await tester.pump();
    expect(find.textContaining('Feedback sent to OpenAI'), findsNothing);
  });

  testWidgets('cancel keeps the draft and a failure says why', (tester) async {
    final lifecycle = _FeedbackLifecycle();
    await _pump(tester, _chat(), lifecycle);

    await _send(tester, '/feedback ');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_composerText(tester), '/feedback ');
    expect(lifecycle.uploads, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text(agentChatFeedbackConsentConfirmLabel));
    await tester.pump();
    lifecycle.answer!.completeError(
      const AgentChatRequestException(
        message: 'Upload refused.',
        code: AgentChatErrorCodes.feedbackFailed,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not send feedback to OpenAI\nUpload refused.'),
      findsOneWidget,
    );
  });

  testWidgets('a chat with no message refuses /feedback as T3 Code does', (
    tester,
  ) async {
    final toasts = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(toasts.add);
    addTearDown(subscription.cancel);
    final lifecycle = _FeedbackLifecycle();
    final repository = _chat(sent: false);
    await _pump(tester, repository, lifecycle);

    await _send(tester, '/feedback');
    expect(find.text(agentChatFeedbackConsentTitle), findsNothing);
    expect(toasts.single.message, agentChatFeedbackNeedsConversationMessage);
    expect(_composerText(tester), '/feedback');
    expect(repository.calls.where((call) => call.$1 == 'send'), isEmpty);
  });

  testWidgets('an older runtime sends /feedback as a message', (tester) async {
    final repository = _chat();
    await _pump(tester, repository, _FeedbackLifecycle(supported: false));

    await _send(tester, '/feedback');
    expect(find.text(agentChatFeedbackConsentTitle), findsNothing);
    final send =
        repository.calls.singleWhere((call) => call.$1 == 'send').$2!
            as AgentChatSendInput;
    expect(send.text, '/feedback');
  });
}
