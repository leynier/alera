import 'dart:async';

import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads dynamic catalogues and uses current model metadata', () async {
    final client = _FakeCodexRuntimeClient();
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });

    final provider = codexChatControllerProvider('tab-1');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    container.read(provider);
    await _settle();
    final state = container.read(provider);
    expect(state.loading, isFalse);
    expect(state.selectedModel, 'gpt-current');
    expect(state.models.single.reasoningEfforts, <String>['xhigh', 'low']);
    expect(state.models.single.defaultReasoningEffort, 'low');
    expect(state.models.single.supportsFastMode, isTrue);
    expect(state.reasoningEffort, 'low');
    expect(state.collaborationModes.single['mode'], 'plan');
    expect(state.skills.single['name'], 'review');
    expect(state.apps.single['name'], 'filesystem');
  });

  test('queues, edits and removes messages while a turn is active', () async {
    final client = _FakeCodexRuntimeClient();
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });

    final provider = codexChatControllerProvider('tab-1');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    container.read(provider);
    await _settle();
    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-1',
        'snapshot': <String, Object?>{'activeTurnId': 'turn-1'},
      }),
    );
    await _settle();
    final controller = container.read(provider.notifier);
    await controller.send('queued prompt');
    expect(
      container.read(provider).queuedMessages.single.text,
      'queued prompt',
    );
    controller.editQueuedMessage(0, text: 'edited prompt');
    expect(
      container.read(provider).queuedMessages.single.text,
      'edited prompt',
    );
    controller.removeQueuedMessage(0);
    expect(container.read(provider).queuedMessages, isEmpty);
  });

  test(
    'forwards attachments, collaboration, permission, speed and review target',
    () async {
      final client = _FakeCodexRuntimeClient();
      final container = ProviderContainer(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_TestSettingsController.new),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      final provider = codexChatControllerProvider('tab-1');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);
      container.read(provider);
      await _settle();
      final controller = container.read(provider.notifier);
      controller.setModel('gpt-current');
      controller.setReasoning('xhigh');
      controller.setSpeed('fast');
      controller.setPermissionMode('never');
      controller.setCollaborationMode('plan');
      await _settle();
      final persisted = container.read(settingsControllerProvider).codexChat;
      expect(persisted.selectedModel, 'gpt-current');
      expect(persisted.reasoningEffort, 'xhigh');
      expect(persisted.speedMode, 'fast');
      expect(persisted.permissionMode, 'never');
      expect(persisted.planMode, isTrue);
      await controller.send(
        'Inspect @lib/main.dart',
        attachments: const <CodexInputAttachment>[
          CodexInputAttachment(path: '/tmp/screenshot.png', isImage: true),
        ],
      );
      await controller.startReview(target: 'baseBranch', delivery: 'inline');
      final turn = client.requests.singleWhere(
        (request) => request.type == 'codex.turn.start',
      );
      final payload = turn.payload;
      expect(payload['serviceTier'], 'fast');
      expect(payload['approvalPolicy'], 'never');
      expect(payload['collaborationMode'], isA<Map<String, Object?>>());
      expect((payload['input'] as List).length, 3);
      final review = client.requests.singleWhere(
        (request) => request.type == 'codex.review.start',
      );
      expect(review.payload['target'], <String, Object?>{'type': 'baseBranch'});
      expect(review.payload['delivery'], 'inline');

      await controller.send('/app filesystem Open the selected file');
      final appTurn = client.requests.lastWhere(
        (request) => request.type == 'codex.turn.start',
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
      expect(appTurn.payload['clientUserMessageId'], isA<String>());
    },
  );

  test('maps command approval for a single turn and for the session', () async {
    final client = _FakeCodexRuntimeClient();
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = codexChatControllerProvider('tab-1');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    container.read(provider);
    await _settle();
    final controller = container.read(provider.notifier);
    const request = CodexPendingRequest(
      id: 7,
      method: 'item/commandExecution/requestApproval',
      params: <String, Object?>{'command': 'git status'},
    );
    await controller.respondApproval(request, accepted: true, forSession: true);
    expect(client.requests.last.payload['result'], <String, Object?>{
      'decision': 'acceptForSession',
    });
  });

  test('plan fallback switches execution and refinement modes', () async {
    final client = _FakeCodexRuntimeClient();
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = codexChatControllerProvider('tab-1');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    container.read(provider);
    await _settle();
    final controller = container.read(provider.notifier);

    controller.setPlanMode(true);
    await controller.implementPlan();
    var turn = client.requests.lastWhere(
      (request) => request.type == 'codex.turn.start',
    );
    expect(container.read(provider).planMode, isFalse);
    expect(turn.payload, isNot(contains('collaborationMode')));
    expect((turn.payload['input'] as List).last, <String, Object?>{
      'type': 'text',
      'text': 'Implement plan',
    });

    await controller.refinePlan('Add tests first');
    turn = client.requests.lastWhere(
      (request) => request.type == 'codex.turn.start',
    );
    expect(container.read(provider).planMode, isTrue);
    expect(turn.payload['collaborationMode'], isA<Map<String, Object?>>());
  });

  test('uses current keyed question answers and permission subsets', () async {
    final client = _FakeCodexRuntimeClient();
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_TestSettingsController.new),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    final provider = codexChatControllerProvider('tab-1');
    final listener = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(listener.close);
    container.read(provider);
    await _settle();
    final controller = container.read(provider.notifier);
    const question = CodexPendingRequest(
      id: 8,
      method: 'item/tool/request_user_input',
      params: <String, Object?>{
        'questions': <Object?>[
          <String, Object?>{'id': 'mode', 'question': 'Choose'},
        ],
      },
    );
    await controller.respondQuestion(question, <String, Object?>{
      'mode': <String>['Careful'],
    });
    expect(client.requests.last.payload['result'], <String, Object?>{
      'answers': <String, Object?>{
        'mode': <String, Object?>{
          'answers': <String>['Careful'],
        },
      },
    });
    const permissions = CodexPendingRequest(
      id: 9,
      method: 'item/permissions/requestApproval',
      params: <String, Object?>{
        'permissions': <String, Object?>{
          'fileSystem': <String, Object?>{
            'read': true,
            'write': false,
            'secret': 'ignored',
          },
          'network': <String, Object?>{'enabled': true, 'secret': 'ignored'},
          'unknown': true,
        },
      },
    );
    await controller.respondApproval(permissions, accepted: true);
    expect(client.requests.last.payload['result'], <String, Object?>{
      'permissions': <String, Object?>{
        'fileSystem': <String, Object?>{'read': true, 'write': false},
        'network': <String, Object?>{'enabled': true},
      },
      'scope': 'turn',
    });
    await controller.respondApproval(permissions, accepted: false);
    expect(client.requests.last.payload['result'], <String, Object?>{
      'permissions': <String, Object?>{},
      'scope': 'turn',
    });
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

final class _FakeCodexRuntimeClient implements RuntimeHostClient {
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();
  final List<_Request> requests = <_Request>[];

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add(_Request(type, payload));
    switch (type) {
      case 'codex.thread.open':
        return <String, Object?>{
          'snapshot': <String, Object?>{
            'events': const <Object?>[],
            'timelineCells': const <Object?>[],
            'pendingRequests': const <Object?>[],
          },
        };
      case 'codex.model.list':
        return <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'id': 'gpt-current',
              'displayName': 'Current Codex',
              'isDefault': true,
              'supportsFastMode': true,
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
      case 'codex.collaborationModes.list':
        return <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'mode': 'plan'},
          ],
        };
      case 'codex.skills.list':
        return <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'name': 'review', 'path': '/skills/review'},
          ],
        };
      case 'codex.apps.list':
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
      default:
        return <String, Object?>{
          'turn': <String, Object?>{'id': 'turn-1'},
        };
    }
  }

  void emit(RuntimeHostEvent event) => _events.add(event);

  void dispose() => _events.close();
}

final class _TestSettingsController extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;

  @override
  Future<void> updateCodexChat(CodexChatSettings settings) async {
    state = state.copyWith(codexChat: settings);
  }
}

final class _Request {
  const _Request(this.type, this.payload);

  final String type;
  final Map<String, Object?> payload;
}
