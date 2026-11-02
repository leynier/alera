import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_link_opener.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_task_fakes.dart';
import '../support/runs_harness.dart';

Map<String, Object?> _chat(String id, {String? tabId, bool archived = false}) =>
    <String, Object?>{
      'chatId': id,
      'workspaceId': 'ws-1',
      'title': id,
      'provider': 'codex',
      'providerInstanceId': 'codex',
      'status': 'ready',
      'tabId': ?tabId,
      'archived': archived,
    };

Future<(FakeChatTaskTransport, RunsTestWorkbench, List<String>)> _pumpLink(
  WidgetTester tester,
  String link,
) async {
  final transport = FakeChatTaskTransport()
    ..chats = <Map<String, Object?>>[
      _chat('chat-open', tabId: 'tab-open'),
      _chat('chat-archived', archived: true),
    ];
  final workbench = RunsTestWorkbench();
  final files = <String>[];
  final container = ProviderContainer(
    overrides: [
      chatTaskRepositoryProvider.overrideWithValue(
        RuntimeAgentChatOrchestrationRepository(transport),
      ),
      agentChatRepositoryProvider.overrideWithValue(
        RuntimeAgentChatRepository(transport),
      ),
      appForegroundProvider.overrideWithValue(const AlwaysForeground()),
      workbenchControllerProvider.overrideWith(() => workbench),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(transport.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => openAgentChatMessageLink(
                context,
                ref,
                link,
                openFile: (path) async => files.add(path),
              ),
              child: const Text('link'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('link'));
  await tester.pumpAndSettle();
  return (transport, workbench, files);
}

void main() {
  testWidgets('a chat link opens that chat on its tab', (tester) async {
    final (transport, workbench, files) = await _pumpLink(
      tester,
      'alera-chat://v1/chat-open?workspace=ws-1',
    );
    expect(workbench.actions, <String>['terminal:tab-open']);
    expect(transport.sent(AgentChatWire.reopen), isEmpty);
    expect(files, isEmpty);
  });

  testWidgets('a chat link leaves an archived chat archived', (tester) async {
    final toasts = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(toasts.add);
    addTearDown(subscription.cancel);
    final (transport, workbench, _) = await _pumpLink(
      tester,
      'alera-chat://v1/chat-archived?workspace=ws-1',
    );
    expect(workbench.actions, isEmpty);
    expect(transport.sent(AgentChatWire.reopen), isEmpty);
    expect(toasts.single.message, startsWith('This chat is archived.'));
  });

  testWidgets('a relative link still opens a workspace file', (tester) async {
    final (_, workbench, files) = await _pumpLink(tester, 'lib/main.dart');
    expect(files, <String>['lib/main.dart']);
    expect(workbench.actions, isEmpty);
  });
}
