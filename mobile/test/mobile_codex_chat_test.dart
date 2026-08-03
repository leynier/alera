import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/codex_chat/presentation/mobile_codex_chat_screen.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
        'answers': <String, List<String>>{
          'mode': <String>['Careful'],
        },
      });
      final approval = state.pendingRequests.firstWhere(
        (request) => request.isApproval,
      );
      await controller.respondApproval(
        approval,
        accepted: true,
        forSession: true,
      );
      expect(client.calls.last.payload['result'], <String, Object?>{
        'decision': 'accept',
        'acceptSettings': <String, Object?>{'forSession': true},
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
    },
  );

  testWidgets('mobile screen renders rich timeline and approval actions', (
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
            body: MobileCodexChatScreen(hostId: 'host-1', tabId: 'tab-1'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('Answer from Codex'), findsOneWidget);
    expect(find.text('Codex Needs Approval'), findsOneWidget);
    expect(find.text('Approve For Session'), findsOneWidget);
    expect(find.text('Current Codex'), findsOneWidget);
    expect(find.text('Message Codex'), findsOneWidget);
  });
}

final class _FakeMobileCodexClient implements MobileCodexClient {
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();
  final List<_Call> calls = <_Call>[];

  @override
  bool get supportsCodexChat => true;

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
              'id': 'answer',
              'kind': 'assistantMessage',
              'status': 'completed',
              'markdownText': 'Answer from Codex',
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
            'reasoningEfforts': <String>['medium', 'high'],
          },
        ],
      };
    }
    if (type == 'codex.skills.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'name': 'review'},
        ],
      };
    }
    if (type == 'codex.apps.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'name': 'filesystem'},
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
