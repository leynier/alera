import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_close_confirmation.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

final WorkspaceTabRecord _tab = WorkspaceTabRecord(
  id: 'tab-1',
  workspaceId: 'ws-1',
  title: 'Fix the build',
  kind: WorkspaceTabKind.agentChat,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  payload: const <String, Object?>{'chatId': 'chat-1'},
);

Future<void> _pumpClose(
  WidgetTester tester,
  FakeAgentChatRepository repository,
  ValueChanged<bool> onResult,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [agentChatRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async => onResult(
              await confirmCloseAgentChatTabs(
                context,
                ref,
                <WorkspaceTabRecord>[_tab],
              ),
            ),
            child: const Text('Close Chat'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Close Chat'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an unopened running chat asks before it can be archived', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository()
      ..snapshots.add(
        () =>
            agentChatSnapshotFixture(status: 'running', activeTurnId: 'turn-1'),
      );
    bool? result;
    await _pumpClose(tester, repository, (value) => result = value);
    expect(find.text('Stop This Chat?'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(repository.snapshotReads, 1);
  });

  testWidgets(
    'an unopened chat with pending input asks before it can be archived',
    (tester) async {
      final repository = FakeAgentChatRepository()
        ..snapshots.add(
          () => agentChatSnapshotFixture(
            requests: <Map<String, Object?>>[
              <String, Object?>{
                'requestId': 'r1',
                'kind': 'command_execution_approval',
                'command': 'make test',
              },
            ],
          ),
        );
      bool? result;
      await _pumpClose(tester, repository, (value) => result = value);
      expect(find.text('Stop This Chat?'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    },
  );

  testWidgets('an unopened idle chat closes without confirmation', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository()
      ..snapshots.add(() => agentChatSnapshotFixture());
    bool? result;
    await _pumpClose(tester, repository, (value) => result = value);
    expect(find.text('Stop This Chat?'), findsNothing);
    expect(result, isTrue);
    expect(repository.snapshotReads, 1);
  });

  testWidgets('an unopened queued chat asks before dropping queued work', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository()
      ..snapshots.add(
        () => agentChatSnapshotFixture(
          queue: <Map<String, Object?>>[
            <String, Object?>{
              'queueId': 'queue-1',
              'text': 'Run the next check',
            },
          ],
        ),
      );
    bool? result;
    await _pumpClose(tester, repository, (value) => result = value);
    expect(find.text('Stop This Chat?'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('a snapshot failure still asks before stopping an unknown chat', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository()
      ..snapshots.add(
        () => throw const AgentChatConnectionException('Unavailable.'),
      );
    bool? result;
    await _pumpClose(tester, repository, (value) => result = value);
    expect(find.text('Stop This Chat?'), findsOneWidget);
    expect(find.textContaining('could not check'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
