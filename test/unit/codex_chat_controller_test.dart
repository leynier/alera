import 'dart:async';

import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

part 'codex_chat_controller_test_support.dart';
part 'codex_chat_controller_request_test_cases.dart';

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

  test(
    'flattens current cwd-grouped skills and ignores disabled skills',
    () async {
      final client = _FakeCodexRuntimeClient()
        ..skills = <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'cwd': '/repo',
              'skills': <Object?>[
                <String, Object?>{
                  'name': 'enabled-skill',
                  'description': 'Enabled',
                  'path': '/skills/enabled/SKILL.md',
                  'enabled': true,
                },
                <String, Object?>{
                  'name': 'disabled-skill',
                  'description': 'Disabled',
                  'path': '/skills/disabled/SKILL.md',
                  'enabled': false,
                },
              ],
              'errors': const <Object?>[],
            },
          ],
        };
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
      final sub = container.listen(
        codexChatControllerProvider('tab-skills'),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await _settle();

      final skills = container
          .read(codexChatControllerProvider('tab-skills'))
          .skills;
      expect(skills.map((skill) => skill['name']), <String>['enabled-skill']);
      expect(skills.single['cwd'], '/repo');

      client.skills = <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'cwd': '/repo',
            'skills': <Object?>[
              <String, Object?>{
                'name': 'refreshed-skill',
                'path': '/skills/refreshed/SKILL.md',
                'enabled': true,
              },
            ],
          },
        ],
      };
      client.emit(
        const RuntimeHostEvent('codexCatalogChanged', <String, Object?>{
          'catalog': 'skills',
        }),
      );
      await _settle();
      expect(
        container
            .read(codexChatControllerProvider('tab-skills'))
            .skills
            .single['name'],
        'refreshed-skill',
      );
    },
  );

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
    await controller.respondApproval(request, decision: 'acceptForSession');
    expect(client.requests.last.payload['result'], <String, Object?>{
      'decision': 'acceptForSession',
    });
    const restricted = CodexPendingRequest(
      id: 8,
      method: 'item/commandExecution/requestApproval',
      params: <String, Object?>{
        'availableDecisions': <Object?>['accept', 'cancel'],
      },
    );
    expect(restricted.supportsApprovalDecision('accept'), isTrue);
    expect(restricted.supportsApprovalDecision('acceptForSession'), isFalse);
    expect(restricted.availableApprovalDecisions, <String>{'accept', 'cancel'});
    const structured = CodexPendingRequest(
      id: 9,
      method: 'item/commandExecution/requestApproval',
      params: <String, Object?>{
        'availableDecisions': <Object?>[
          <String, Object?>{
            'acceptWithExecpolicyAmendment': <String, Object?>{
              'execpolicy_amendment': <Object?>['prefix_rule'],
            },
          },
        ],
      },
    );
    final structuredDecision = structured.approvalDecisionValue(
      'acceptWithExecpolicyAmendment',
    );
    expect(structured.availableApprovalDecisions, <String>{
      'acceptWithExecpolicyAmendment',
    });
    expect(
      structured.approvalDecisionName(structuredDecision),
      'acceptWithExecpolicyAmendment',
    );
    await controller.respondApproval(structured, decision: structuredDecision);
    expect(client.requests.last.payload['result'], <String, Object?>{
      'decision': structuredDecision,
    });
  });

  test(
    'sends selected skills, apps, files, images and audio as typed input',
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

      await container
          .read(provider.notifier)
          .send(
            'Use these inputs and @docs/my notes.md',
            draftItems: const <CodexDraftItem>[
              CodexDraftItem(
                id: 'skill-review',
                kind: CodexDraftItemKind.skill,
                name: 'review',
                path: '/skills/review',
              ),
              CodexDraftItem(
                id: 'app-filesystem',
                kind: CodexDraftItemKind.app,
                name: 'filesystem',
                path: 'app://connector-filesystem',
                tokenText: r'$filesystem',
              ),
              CodexDraftItem(
                id: 'mention-docs/my notes.md',
                kind: CodexDraftItemKind.mention,
                name: 'my notes.md',
                path: 'docs/my notes.md',
                tokenText: '@docs/my notes.md',
              ),
            ],
            attachments: const <CodexInputAttachment>[
              CodexInputAttachment(path: '/tmp/image.png', isImage: true),
              CodexInputAttachment(path: '/tmp/prompt.wav', isImage: false),
              CodexInputAttachment(
                path: '/tmp/notes.txt',
                displayName: 'notes.txt',
                isImage: false,
              ),
            ],
          );
      final turn = client.requests.lastWhere(
        (request) => request.type == 'codex.turn.start',
      );
      expect(turn.payload['input'], <Object?>[
        <String, Object?>{
          'type': 'skill',
          'name': 'review',
          'path': '/skills/review',
        },
        <String, Object?>{
          'type': 'mention',
          'name': 'filesystem',
          'path': 'app://connector-filesystem',
        },
        <String, Object?>{
          'type': 'workspaceFile',
          'name': 'my notes.md',
          'path': 'docs/my notes.md',
        },
        <String, Object?>{
          'type': 'text',
          'text': 'Use these inputs and @docs/my notes.md',
        },
        <String, Object?>{'type': 'localImage', 'path': '/tmp/image.png'},
        <String, Object?>{'type': 'localAudio', 'path': '/tmp/prompt.wav'},
        <String, Object?>{
          'type': 'localFile',
          'name': 'notes.txt',
          'path': '/tmp/notes.txt',
        },
      ]);
    },
  );

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

  registerCodexChatControllerRequestTests();
}
