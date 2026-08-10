import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/codex_chat/presentation/mobile_codex_chat_screen.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

void main() {
  test('mobile rebuilds a coherent timeline from legacy raw events', () {
    final state = MobileCodexState.fromSnapshot(<String, Object?>{
      'events': <Object?>[
        <String, Object?>{
          'method': 'turn/started',
          'params': <String, Object?>{
            'turn': <String, Object?>{'id': 'turn-legacy'},
          },
        },
        <String, Object?>{
          'method': 'item/agentMessage/delta',
          'params': <String, Object?>{
            'turnId': 'turn-legacy',
            'itemId': 'answer',
            'delta': 'Hello',
          },
        },
        <String, Object?>{
          'method': 'item/agentMessage/delta',
          'params': <String, Object?>{
            'turnId': 'turn-legacy',
            'itemId': 'answer',
            'delta': ' world',
          },
        },
        <String, Object?>{
          'method': 'turn/completed',
          'params': <String, Object?>{'turnId': 'turn-legacy'},
        },
      ],
    });
    expect(state.timelineCells, hasLength(2));
    expect(state.timelineCells.last.kind, 'assistantMessage');
    expect(state.timelineCells.last.displayText, 'Hello world');
    expect(state.timelineCells.last.isStreaming, isFalse);
  });

  test('mobile replaces full diff snapshots instead of appending them', () {
    var cells = MobileCodexTimelineReducer.reduce(
      const <MobileCodexTimelineCell>[],
      <String, Object?>{
        'method': 'turn/diff/updated',
        'params': <String, Object?>{
          'turnId': 'turn-1',
          'diff': 'first snapshot',
        },
      },
    );
    cells = MobileCodexTimelineReducer.reduce(cells, <String, Object?>{
      'method': 'turn/diff/updated',
      'params': <String, Object?>{
        'turnId': 'turn-1',
        'diff': 'second snapshot',
      },
    });
    expect(
      cells.singleWhere((cell) => cell.id == 'diff-turn-1').detailsText,
      'second snapshot',
    );
  });

  test('mobile tracks context compaction once through completion', () {
    var cells = MobileCodexTimelineReducer.reduce(
      const <MobileCodexTimelineCell>[],
      <String, Object?>{
        'method': 'item/started',
        'params': <String, Object?>{
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'compact-1',
            'type': 'contextCompaction',
            'title': 'Context automatically compacting',
          },
        },
      },
    );
    expect(cells.single.kind, 'toolCall');
    expect(cells.single.title, 'Compacting');
    expect(cells.single.isStreaming, isTrue);

    cells = MobileCodexTimelineReducer.reduce(cells, <String, Object?>{
      'method': 'item/completed',
      'params': <String, Object?>{
        'turnId': 'turn-1',
        'item': <String, Object?>{
          'id': 'compact-1',
          'type': 'contextCompaction',
        },
      },
    });
    cells = MobileCodexTimelineReducer.reduce(cells, <String, Object?>{
      'method': 'thread/compacted',
      'params': <String, Object?>{'turnId': 'turn-1'},
    });
    expect(cells, hasLength(1));
    expect(cells.single.id, 'item-compact-1');
    expect(cells.single.title, 'Compacted');
    expect(cells.single.status, 'completed');
    expect(cells.single.isStreaming, isFalse);
  });

  test('mobile exposes only the latest actionable plan', () {
    MobileCodexState state(Object? pendingRequests) =>
        MobileCodexState.fromSnapshot(<String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'user-old',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Old request',
            },
            <String, Object?>{
              'id': 'plan-old',
              'kind': 'plan',
              'status': 'completed',
              'markdownText': 'Old plan',
            },
            <String, Object?>{
              'id': 'user-latest',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Latest request',
            },
            <String, Object?>{
              'id': 'plan-latest',
              'kind': 'plan',
              'status': 'completed',
              'markdownText': 'Latest plan',
            },
          ],
          'pendingRequests': pendingRequests,
        });

    expect(state(const <Object?>[]).shouldShowImplementPlan, isTrue);
    expect(
      state(<Object?>[
        <String, Object?>{
          'id': 3,
          'method': 'item/tool/request_user_input',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'plan',
                'question': 'Implement this plan?',
              },
            ],
          },
        },
      ]).shouldShowImplementPlan,
      isFalse,
    );
  });

  test(
    'mobile controller exposes catalogues, options, questions and queue actions',
    () async {
      final client = _FakeMobileCodexClient();
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider(
            'host-1',
          ).overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = mobileCodexControllerProvider('host-1', 'tab-1');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      await container.read(provider.future);
      final controller = container.read(provider.notifier);
      var state = container.read(provider).value!;
      expect(state.selectedModel, 'gpt-current');
      expect(state.models.single.contextWindowTokens, 128000);
      expect(state.models.single.reasoningEfforts, <String>['xhigh', 'low']);
      expect(state.models.single.defaultReasoningEffort, 'low');
      expect(state.models.single.supportsFastMode, isTrue);
      expect(state.reasoningEffort, 'low');
      expect(state.skills.single['name'], 'review');
      expect(state.apps.single['name'], 'filesystem');
      final question = state.pendingRequests.firstWhere(
        (request) => request.isQuestion,
      );
      expect(question.questions.single.options, hasLength(2));

      await controller.respondQuestion(question, <String, List<String>>{
        'mode': <String>['Careful'],
      });
      expect(client.calls.last.payload['result'], <String, Object?>{
        'answers': <String, Object?>{
          'mode': <String, Object?>{
            'answers': <String>['Careful'],
          },
        },
      });
      final approval = state.pendingRequests.firstWhere(
        (request) => request.isApproval,
      );
      await controller.respondApproval(
        approval,
        decision: approval.approvalDecisionValue('acceptForSession'),
      );
      expect(client.calls.last.payload['result'], <String, Object?>{
        'decision': 'acceptForSession',
      });
      final mcp = state.pendingRequests.firstWhere(
        (request) => request.isElicitation,
      );
      await controller.respondElicitation(
        mcp,
        action: 'accept',
        content: const <String, Object?>{'name': 'Alera'},
      );
      expect(client.calls.last.payload['result'], <String, Object?>{
        'action': 'accept',
        'content': <String, Object?>{'name': 'Alera'},
      });
      await controller.send('first');
      client.emit(
        const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-1',
          'snapshot': <String, Object?>{'activeTurnId': 'turn-1'},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await controller.send('queued');
      state = container.read(provider).value!;
      expect(state.queuedMessages.single['text'], 'queued');
      controller.editQueuedMessage(0, 'edited');
      expect(
        container.read(provider).value!.queuedMessages.single['text'],
        'edited',
      );
      controller.removeQueuedMessage(0);
      expect(container.read(provider).value!.queuedMessages, isEmpty);
      controller.setSpeed('fast');
      controller.setPermissionMode('never');
      controller.setPlanMode(true);
      await controller.review(target: 'baseBranch', delivery: 'inline');
      await controller.rename('Renamed Thread');
      expect(
        client.calls.any((call) => call.type == 'codex.review.start'),
        isTrue,
      );
      expect(
        client.calls.any((call) => call.type == 'codex.thread.rename'),
        isTrue,
      );
      final turn = client.calls.lastWhere(
        (call) => call.type == 'codex.turn.start',
      );
      expect(turn.payload['clientUserMessageId'], isA<String>());
      client.emit(
        const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'tab-1',
          'snapshot': <String, Object?>{},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await controller.send('/app filesystem Open the selected file');
      final appTurn = client.calls.lastWhere(
        (call) => call.type == 'codex.turn.start',
      );
      expect((appTurn.payload['input'] as List).first, <String, Object?>{
        'type': 'mention',
        'name': 'filesystem',
        'path': 'app://connector-filesystem',
      });
      expect((appTurn.payload['input'] as List)[1], <String, Object?>{
        'type': 'text',
        'text': r'$filesystem Open the selected file',
      });
      await controller.send('/skill review');
      final skillTurn = client.calls.lastWhere(
        (call) => call.type == 'codex.turn.start',
      );
      expect((skillTurn.payload['input'] as List).first, <String, Object?>{
        'type': 'skill',
        'name': 'review',
        'path': '/skills/review',
      });
      expect((skillTurn.payload['input'] as List)[1], <String, Object?>{
        'type': 'text',
        'text': r'$review',
      });

      controller.setPlanMode(true);
      await controller.implementPlan();
      final implementationTurn = client.calls.lastWhere(
        (call) => call.type == 'codex.turn.start',
      );
      expect(container.read(provider).value!.planMode, isFalse);
      expect(implementationTurn.payload['collaborationMode'], <String, Object?>{
        'mode': 'default',
        'settings': <String, Object?>{
          'model': 'gpt-current',
          'reasoning_effort': 'low',
        },
      });
      expect(
        (implementationTurn.payload['input'] as List).last,
        <String, Object?>{'type': 'text', 'text': 'Implement plan'},
      );

      await controller.refinePlan('Add tests first');
      final refinementTurn = client.calls.lastWhere(
        (call) => call.type == 'codex.turn.start',
      );
      expect(container.read(provider).value!.planMode, isTrue);
      expect(
        refinementTurn.payload['collaborationMode'],
        isA<Map<String, Object?>>(),
      );
    },
  );

  testWidgets('mobile screen renders rich timeline and the current request', (
    tester,
  ) async {
    final client = _FakeMobileCodexClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileCodexClientProvider(
            'host-1',
          ).overrideWith((ref) async => client),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MobileCodexChatScreen(
              hostId: 'host-1',
              tabId: 'tab-1',
              workspaceId: 'workspace-1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('Answer from Codex'), findsOneWidget);
    expect(find.text('Choose a mode'), findsOneWidget);
    expect(find.text('Fast'), findsOneWidget);
    expect(find.text('Careful'), findsOneWidget);
    expect(find.byType(GptMarkdown), findsWidgets);
    expect(find.textContaining('Current Codex'), findsOneWidget);
    expect(find.textContaining('Ask Codex anything'), findsOneWidget);
  });
}

final class _FakeMobileCodexClient implements MobileCodexClient {
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();
  final List<_Call> calls = <_Call>[];

  @override
  bool get supportsCodexChat => true;

  @override
  bool get supportsCodexSessions => true;

  @override
  bool get supportsCodexTurnPolicy => true;

  @override
  Stream<MobileRuntimeEvent> get events => _events.stream;

  @override
  Future<Never> createCodexTab(String workspaceId) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, Object?>> codexRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    calls.add(_Call(type, payload));
    if (type == 'codex.thread.open') {
      return <String, Object?>{
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'request',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Inspect the workspace',
            },
            <String, Object?>{
              'id': 'answer',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Answer from Codex',
            },
            <String, Object?>{
              'id': 'plan',
              'kind': 'plan',
              'status': 'completed',
              'markdownText': '1. Inspect\n2. Implement',
            },
          ],
          'pendingRequests': <Object?>[
            <String, Object?>{
              'id': 9,
              'method': 'item/tool/request_user_input',
              'params': <String, Object?>{
                'questions': <Object?>[
                  <String, Object?>{
                    'id': 'mode',
                    'question': 'Choose a mode',
                    'options': <Object?>[
                      <String, Object?>{'label': 'Fast'},
                      <String, Object?>{'label': 'Careful'},
                    ],
                  },
                ],
              },
            },
            <String, Object?>{
              'id': 10,
              'method': 'item/commandExecution/requestApproval',
              'params': <String, Object?>{'command': 'git status'},
            },
            <String, Object?>{
              'id': 11,
              'method': 'mcpServer/elicitation/request',
              'params': <String, Object?>{
                'mode': 'form',
                'requestedSchema': <String, Object?>{
                  'type': 'object',
                  'properties': <String, Object?>{
                    'name': <String, Object?>{'type': 'string'},
                  },
                },
              },
            },
          ],
        },
      };
    }
    if (type == 'codex.model.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': 'gpt-current',
            'displayName': 'Current Codex',
            'isDefault': true,
            'contextWindowTokens': 128000,
            'supportedReasoningEfforts': <Object?>[
              <String, Object?>{'reasoningEffort': 'xhigh'},
              <String, Object?>{'reasoningEffort': 'low'},
            ],
            'defaultReasoningEffort': 'low',
            'additionalSpeedTiers': <String>['fast'],
            'serviceTiers': <Object?>[
              <String, Object?>{'id': 'priority', 'name': 'Fast'},
            ],
          },
        ],
      };
    }
    if (type == 'codex.skills.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'name': 'review', 'path': '/skills/review'},
        ],
      };
    }
    if (type == 'codex.apps.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'name': 'filesystem',
            'slug': 'filesystem',
            'id': 'connector-filesystem',
            'connectorId': 'connector-filesystem',
          },
        ],
      };
    }
    if (type == 'codex.collaborationModes.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'mode': 'plan'},
        ],
      };
    }
    return <String, Object?>{};
  }

  void emit(MobileRuntimeEvent event) => _events.add(event);

  void dispose() => _events.close();
}

final class _Call {
  const _Call(this.type, this.payload);

  final String type;
  final Map<String, Object?> payload;
}
