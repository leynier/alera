import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_chat_actions.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_task_fakes.dart';
import '../support/runs_harness.dart';

class _NoRemoteHosts extends RemoteHostsController {
  @override
  RemoteHostsState build() => const RemoteHostsState(loading: false);
}

Future<(ProviderContainer, RunsTestWorkbench)> _pump(
  WidgetTester tester,
  FakeChatTaskTransport transport,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var ids = 0;
  final workbench = RunsTestWorkbench();
  final container = ProviderContainer(
    overrides: [
      chatTaskRepositoryProvider.overrideWithValue(
        RuntimeAgentChatOrchestrationRepository(transport),
      ),
      agentChatRepositoryProvider.overrideWithValue(
        RuntimeAgentChatRepository(transport),
      ),
      agentChatIdGeneratorProvider.overrideWithValue(() => 'request-${ids++}'),
      appForegroundProvider.overrideWithValue(const AlwaysForeground()),
      workbenchControllerProvider.overrideWith(() => workbench),
      remoteHostsControllerProvider.overrideWith(_NoRemoteHosts.new),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(transport.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(
          body: Center(
            child: ChatTaskChatMenuButton(
              chatId: 'chat-parent',
              workspaceId: 'ws-1',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, workbench);
}

Future<void> _delegate(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('chatTaskChatMenu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delegate Task').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey<String>('delegateTask')),
      matching: find.byType(TextField),
    ),
    'Summarize the open pull requests',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey<String>('delegateSubmit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Delegate Task from a chat reports back to it and opens nothing',
    (tester) async {
      final transport = FakeChatTaskTransport(personParent: true);
      final (container, workbench) = await _pump(tester, transport);
      await _delegate(tester);

      final delegate = transport
          .sent(AgentChatOrchestrationWire.delegate)
          .single;
      expect(delegate['parentChatId'], 'chat-parent');
      expect(delegate['target'], <String, Object?>{
        'workspace': <String, Object?>{'workspaceId': 'ws-1'},
      });
      expect(container.read(activityNavigationProvider).visible, isFalse);
      expect(workbench.actions, isEmpty);
    },
  );

  testWidgets('an older runtime delegates without naming a parent', (
    tester,
  ) async {
    final transport = FakeChatTaskTransport();
    final (container, workbench) = await _pump(tester, transport);
    await _delegate(tester);

    final delegate = transport.sent(AgentChatOrchestrationWire.delegate).single;
    expect(delegate.containsKey('parentChatId'), isFalse);
    expect(container.read(activityNavigationProvider).visible, isFalse);
    expect(workbench.actions, isEmpty);
  });

  testWidgets('the menu hides on a runtime without chat tasks', (tester) async {
    await _pump(tester, FakeChatTaskTransport(orchestration: false));
    expect(
      find.byKey(const ValueKey<String>('chatTaskChatMenu')),
      findsNothing,
    );
  });
}
