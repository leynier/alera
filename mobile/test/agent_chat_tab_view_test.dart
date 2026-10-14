import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tab_view.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

Future<FakeAgentChatClient> _pumpChat(
  WidgetTester tester,
  Map<String, Object?> snapshot, {
  Set<String>? capabilities,
}) async {
  final client = FakeAgentChatClient(capabilities: capabilities);
  client.handlers['agentChat.snapshot'] = (_) => snapshot;
  final workspace = FakeTerminalClient();
  addTearDown(workspace.dispose);
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatDraftStoreProvider.overrideWithValue(AgentChatDraftStore()),
        mobileAgentChatClientProvider('host')
            .overrideWith((ref) async => client),
        workspaceClientProvider('host').overrideWith((ref) async => workspace),
        mobileAiDictationSettingsControllerProvider.overrideWith(
          FakeMobileAiDictationSettingsController.new,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: AgentChatTabView(
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
  return client;
}

Map<String, Object?> _request(
  String kind, {
  List<String> decisions = const <String>[],
  List<Map<String, Object?>> questions = const <Map<String, Object?>>[],
}) => <String, Object?>{
  'requestId': 'request-1',
  'kind': kind,
  'turnId': 'turn-1',
  'createdAt': '2026-10-12T10:00:01Z',
  'command': 'rm -rf build',
  'decisions': decisions,
  'questions': questions,
};

void main() {
  testWidgets('a finished turn shows its prompt, folded work and answer', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      agentChatSnapshot(
        turns: <Map<String, Object?>>[agentChatTurn('turn-1')],
        items: <Map<String, Object?>>[
          agentChatItem('prompt', type: 'user_message', text: 'Fix the build'),
          agentChatItem(
            'command',
            type: 'command_execution',
            normalized: <String, Object?>{'command': 'npm test', 'exitCode': 0},
          ),
          agentChatItem(
            'edit',
            type: 'file_change',
            normalized: <String, Object?>{
              'changes': <Object?>[
                <String, Object?>{'path': 'lib/main.dart', 'kind': 'update'},
              ],
            },
          ),
          agentChatItem('answer', text: 'The build passes now.'),
        ],
      ),
    );
    expect(find.text('Fix the build'), findsOneWidget);
    expect(
      find.textContaining('The build passes now.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Worked for 4s'), findsOneWidget);
    expect(find.text('Ran npm test'), findsNothing);

    await tester.tap(find.text('Worked for 4s'));
    await tester.pumpAndSettle();
    expect(find.text('Edited 1 file, ran 1 command'), findsOneWidget);
  });

  testWidgets('an approval offers only the runtime decisions', (tester) async {
    final client = await _pumpChat(
      tester,
      agentChatSnapshot(
        pendingRequests: <Map<String, Object?>>[
          _request(
            'command_execution_approval',
            decisions: <String>['accept', 'acceptForSession', 'decline'],
          ),
        ],
      ),
    );
    client.handlers['agentChat.respond'] = (_) => <String, Object?>{
      'resolved': true,
    };
    expect(find.text('Run Command?'), findsOneWidget);
    expect(find.text(r'$ rm -rf build'), findsOneWidget);
    expect(find.text('Allow Once'), findsOneWidget);
    expect(find.text('Allow For Session'), findsOneWidget);
    // The third runtime decision is one tap further, never dropped.
    expect(find.text('Decline'), findsNothing);
    expect(find.byTooltip('More Decisions'), findsOneWidget);
    expect(find.text('Cancel Turn'), findsNothing);
    expect(
      find.text('The agent is waiting for your decision.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Allow Once'));
    await tester.pumpAndSettle();
    final payload = client.payloadsOf('agentChat.respond').single;
    expect(payload['runtimeRequestId'], 'request-1');
    expect(payload['workspaceId'], 'workspace-1');
    expect(payload['response'], <String, Object?>{
      'type': 'approval',
      'decision': 'accept',
    });
  });

  testWidgets('a docked question answers with the chosen option', (
    tester,
  ) async {
    final client = await _pumpChat(
      tester,
      agentChatSnapshot(
        pendingRequests: <Map<String, Object?>>[
          _request(
            'tool_user_input',
            questions: <Map<String, Object?>>[
              <String, Object?>{
                'id': 'target',
                'header': 'Deploy target',
                'question': 'Where should this go?',
                'options': <Object?>[
                  <String, Object?>{'label': 'Staging', 'value': 'staging'},
                  <String, Object?>{'label': 'Production'},
                ],
              },
            ],
          ),
        ],
      ),
    );
    client.handlers['agentChat.respond'] = (_) => <String, Object?>{
      'resolved': true,
    };
    expect(find.text('Deploy target'), findsOneWidget);
    await tester.tap(find.text('Staging'));
    await tester.pumpAndSettle();
    expect(
      client.payloadsOf('agentChat.respond').single['response'],
      <String, Object?>{
        'type': 'userInput',
        'answers': <String, Object?>{
          'target': <String>['staging'],
        },
      },
    );
  });

  testWidgets('input another chat sent reads as a notice, not a prompt', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      agentChatSnapshot(
        items: <Map<String, Object?>>[
          agentChatItem(
            'relay',
            type: 'user_message',
            text: 'Please review the migration.',
            origin: <String, Object?>{
              'kind': 'chatMessage',
              'senderChatId': 'chat-2',
            },
          ),
        ],
      ),
    );
    expect(find.text('Message from another chat'), findsOneWidget);
    expect(
      find.textContaining('Please review the migration.', findRichText: true),
      findsNothing,
    );
    await tester.tap(find.text('Message from another chat'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Please review the migration.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('an archived chat is read-only and offers Reopen', (
    tester,
  ) async {
    final client = await _pumpChat(tester, agentChatSnapshot(archived: true));
    client.handlers['agentChat.reopen'] = (_) => <String, Object?>{
      'chatId': 'chat-1',
      'tabId': 'tab-new',
      'snapshot': agentChatSnapshot(),
    };
    expect(
      find.text('This chat is archived. Its history is kept on the host.'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();
    expect(client.payloadsOf('agentChat.reopen'), hasLength(1));
  });

  testWidgets('Send clears the composer and asks the runtime', (tester) async {
    final client = await _pumpChat(tester, agentChatSnapshot());
    client.handlers['agentChat.send'] = (_) => <String, Object?>{
      'delivery': 'started',
    };
    await tester.enterText(find.byType(TextField), 'Add a changelog entry');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(
      client.payloadsOf('agentChat.send').single['text'],
      'Add a changelog entry',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('Add a changelog entry'), findsOneWidget);
  });

  testWidgets('a chat nothing was sent to shows its ready state', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      agentChatSnapshot(session: agentChatSession(status: 'stopped')),
    );
    expect(find.text('Send a message to start.'), findsOneWidget);
    expect(find.text('/repo'), findsOneWidget);
    expect(find.text('The agent session stopped.'), findsNothing);
  });

  testWidgets('a failed turn stays open with its failing action', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      agentChatSnapshot(
        turns: <Map<String, Object?>>[
          agentChatTurn('turn-1', status: 'failed'),
        ],
        items: <Map<String, Object?>>[
          agentChatItem('prompt', type: 'user_message', text: 'Fix the build'),
          agentChatItem(
            'read',
            type: 'command_execution',
            normalized: <String, Object?>{
              'command': 'cat a.txt',
              'exitCode': 0,
            },
          ),
          agentChatItem(
            'command',
            type: 'command_execution',
            status: 'failed',
            normalized: <String, Object?>{'command': 'npm test', 'exitCode': 1},
          ),
        ],
      ),
    );
    expect(find.text('Failed after 4s'), findsOneWidget);
    expect(find.textContaining('npm test'), findsWidgets);
  });

  testWidgets('approvals dock ahead of questions, one page at a time', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      agentChatSnapshot(
        pendingRequests: <Map<String, Object?>>[
          <String, Object?>{
            ..._request(
              'tool_user_input',
              questions: <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'target',
                  'header': 'Deploy target',
                  'question': 'Where should this go?',
                  'options': <Object?>[
                    <String, Object?>{'label': 'Staging'},
                  ],
                },
              ],
            ),
            'requestId': 'question-1',
            'createdAt': '2026-10-12T10:00:00Z',
          },
          <String, Object?>{
            ..._request(
              'command_execution_approval',
              decisions: <String>['accept', 'decline'],
            ),
            'requestId': 'approval-1',
            'createdAt': '2026-10-12T10:00:05Z',
          },
        ],
      ),
    );
    expect(find.text('Request 1 of 2'), findsOneWidget);
    expect(find.text('Run Command?'), findsOneWidget);
    expect(find.text('Deploy target'), findsNothing);
    await tester.tap(find.byTooltip('Next Request'));
    await tester.pumpAndSettle();
    expect(find.text('Request 2 of 2'), findsOneWidget);
    expect(find.text('Deploy target'), findsOneWidget);
  });

  testWidgets('a long press on Send steers where the agent allows it', (
    tester,
  ) async {
    final client = await _pumpChat(
      tester,
      agentChatSnapshot(
        turns: <Map<String, Object?>>[
          agentChatTurn('turn-1', status: 'running', completedAt: null),
        ],
        items: <Map<String, Object?>>[
          agentChatItem('prompt', type: 'user_message', text: 'Build it'),
        ],
        session: agentChatSession(
          status: 'running',
          activeTurnId: 'turn-1',
          steer: true,
        ),
      ),
    );
    client.handlers['agentChat.send'] = (_) => <String, Object?>{
      'delivery': 'steered',
    };
    await tester.enterText(find.byType(TextField), 'Use the other file');
    await tester.pump();
    await tester.longPress(find.byIcon(AleraIcons.queuedMessage));
    await tester.pump();
    expect(client.payloadsOf('agentChat.send').single['delivery'], 'steer');
  });

  testWidgets('folds the person opened survive leaving the tab', (
    tester,
  ) async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot(
      turns: <Map<String, Object?>>[agentChatTurn('turn-1')],
      items: <Map<String, Object?>>[
        agentChatItem('prompt', type: 'user_message', text: 'Fix the build'),
        agentChatItem(
          'command',
          type: 'command_execution',
          normalized: <String, Object?>{'command': 'npm test', 'exitCode': 0},
        ),
        agentChatItem(
          'second',
          type: 'command_execution',
          normalized: <String, Object?>{
            'command': 'npm run lint',
            'exitCode': 0,
          },
        ),
        agentChatItem('answer', text: 'Done.'),
      ],
    );
    final workspace = FakeTerminalClient();
    addTearDown(workspace.dispose);
    var shown = true;
    late StateSetter toggle;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentChatDraftStoreProvider.overrideWithValue(AgentChatDraftStore()),
          mobileAgentChatClientProvider('host')
              .overrideWith((ref) async => client),
          workspaceClientProvider('host')
              .overrideWith((ref) async => workspace),
          mobileAiDictationSettingsControllerProvider.overrideWith(
            FakeMobileAiDictationSettingsController.new,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                toggle = setState;
                return shown
                    ? const AgentChatTabView(
                        hostId: 'host',
                        workspaceId: 'workspace-1',
                        chatId: 'chat-1',
                        provider: 'codex',
                      )
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Worked for 4s'));
    await tester.pumpAndSettle();
    expect(find.text('Ran 2 commands'), findsOneWidget);

    toggle(() => shown = false);
    await tester.pumpAndSettle();
    toggle(() => shown = true);
    await tester.pumpAndSettle();
    expect(find.text('Ran 2 commands'), findsOneWidget);
  });

  testWidgets('an older runtime explains that it needs an update', (
    tester,
  ) async {
    await _pumpChat(tester, agentChatSnapshot(), capabilities: <String>{});
    expect(find.text('Update required'), findsOneWidget);
  });
}
