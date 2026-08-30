import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_mobile_codex_client.dart';

void main() {
  test('mobile controller exposes catalogues, options, questions and queue actions', () async {
    final client = FakeMobileCodexClient();
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider('host-1').overrideWith((ref) async => client),
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

    const nonblockingQuestion = MobileCodexPendingRequest(
      id: 7,
      method: 'item/tool/request_user_input',
      params: <String, Object?>{'isBlocking': false},
    );
    await controller.snoozeQuestionAutoResolution(nonblockingQuestion);
    expect(client.calls.last.type, 'codex.request.snooze');
    expect(client.calls.last.payload, <String, Object?>{'requestId': 7});

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
    const proposedApproval = MobileCodexPendingRequest(
      id: 11,
      method: 'item/commandExecution/requestApproval',
      params: <String, Object?>{
        'proposedExecpolicyAmendment': <Object?>['git', 'status'],
      },
    );
    expect(proposedApproval.supportsApprovalDecision('accept'), isTrue);
    expect(
      proposedApproval.supportsApprovalDecision('acceptForSession'),
      isTrue,
    );
    expect(proposedApproval.supportsApprovalDecision('cancel'), isTrue);
    expect(
      proposedApproval.supportsApprovalDecision(
        'acceptWithExecpolicyAmendment',
      ),
      isTrue,
    );
    expect(
      proposedApproval.approvalDecisionValue('acceptWithExecpolicyAmendment'),
      <String, Object?>{
        'acceptWithExecpolicyAmendment': <String, Object?>{
          'execpolicy_amendment': <Object?>['git', 'status'],
        },
      },
    );
    const plainFileApproval = MobileCodexPendingRequest(
      id: 14,
      method: 'item/fileChange/requestApproval',
      params: <String, Object?>{},
    );
    expect(
      plainFileApproval.supportsApprovalDecision(
        'acceptWithExecpolicyAmendment',
      ),
      isFalse,
    );
    expect(
      plainFileApproval.supportsApprovalDecision('applyNetworkPolicyAmendment'),
      isFalse,
    );
    const amendedApproval = MobileCodexPendingRequest(
      id: 12,
      method: 'item/commandExecution/requestApproval',
      params: <String, Object?>{
        'availableDecisions': <Object?>[
          <String, Object?>{
            'acceptWithExecpolicyAmendment': <String, Object?>{
              'command': 'git status',
            },
          },
          'decline',
        ],
      },
    );
    await controller.respondApproval(
      amendedApproval,
      decision: amendedApproval.approvalDecisionValue(
        'acceptWithExecpolicyAmendment',
      ),
    );
    expect(client.calls.last.payload['result'], <String, Object?>{
      'decision': <String, Object?>{
        'acceptWithExecpolicyAmendment': <String, Object?>{
          'command': 'git status',
        },
      },
    });
    const legacyApproval = MobileCodexPendingRequest(
      id: 13,
      method: 'execCommandApproval',
      params: <String, Object?>{},
    );
    await controller.respondApproval(
      legacyApproval,
      decision: 'acceptForSession',
    );
    expect(client.calls.last.payload['result'], <String, Object?>{
      'decision': 'approved_for_session',
    });
    await controller.respondApproval(legacyApproval, decision: 'decline');
    expect(client.calls.last.payload['result'], <String, Object?>{
      'decision': <String, Object?>{
        'denied': <String, Object?>{'rejection': 'Denied by user.'},
      },
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
    client.emit(
      const MobileRuntimeEvent('codexCatalogChanged', <String, Object?>{
        'catalog': 'skills',
      }),
    );
    await Future<void>.delayed(.zero);
    expect(
      client.calls.where((call) => call.type == 'codex.skills.list'),
      hasLength(2),
    );
    expect(
      client.calls.where((call) => call.type == 'codex.apps.list'),
      hasLength(1),
    );
    client.emit(
      const MobileRuntimeEvent('codexCatalogChanged', <String, Object?>{
        'catalog': 'apps',
      }),
    );
    await Future<void>.delayed(.zero);
    expect(
      client.calls.where((call) => call.type == 'codex.apps.list'),
      hasLength(2),
    );
    client.emit(
      const MobileRuntimeEvent('codexCatalogChanged', <String, Object?>{
        'catalog': 'account',
      }),
    );
    await Future<void>.delayed(.zero);
    expect(
      client.calls.where((call) => call.type == 'codex.model.list'),
      hasLength(2),
    );
    expect(
      client.calls.where(
        (call) => call.type == 'codex.collaborationModes.list',
      ),
      hasLength(2),
    );
    await controller.send('first');
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-1',
        'snapshot': <String, Object?>{'activeTurnId': 'turn-1'},
      }),
    );
    await Future<void>.delayed(.zero);
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
    await controller.steer(
      'Use this too',
      attachments: const <Map<String, Object?>>[
        <String, Object?>{
          'type': 'file',
          'origin': 'attachment',
          'name': 'steer.csv',
          'path': '/tmp/steer.csv',
        },
      ],
    );
    final steer = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.steer',
    );
    expect(steer.payload['userMessage'], <String, Object?>{
      'text': 'Use this too',
      'attachments': <Map<String, Object?>>[
        <String, Object?>{
          'path': '/tmp/steer.csv',
          'displayName': 'steer.csv',
          'kind': 'file',
          'origin': 'attachment',
          'isImage': false,
          'isDirectory': false,
        },
      ],
    });
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
    await Future<void>.delayed(.zero);
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

    controller.setPermissionMode('untrusted');
    await controller.send('ask permission');
    var permissionTurn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(permissionTurn.payload['approvalPolicy'], 'untrusted');
    expect(permissionTurn.payload['approvalsReviewer'], 'user');
    expect(permissionTurn.payload['sandboxPolicy'], <String, Object?>{
      'type': 'workspaceWrite',
      'writableRoots': const <String>[],
      'networkAccess': false,
    });
    controller.setPermissionMode('on-request');
    await controller.send('legacy approval mode');
    permissionTurn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(permissionTurn.payload['approvalsReviewer'], 'user');
    controller.setPermissionMode('auto-review');
    await controller.send('approve for me');
    permissionTurn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(permissionTurn.payload['approvalsReviewer'], 'auto_review');
    controller.setPermissionMode('never');
    await controller.send('full access');
    permissionTurn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(permissionTurn.payload['approvalPolicy'], 'never');
    expect(permissionTurn.payload['approvalsReviewer'], 'user');
    expect(permissionTurn.payload['sandboxPolicy'], <String, Object?>{
      'type': 'dangerFullAccess',
    });

    await controller.send(
      'config/AGENTS.md hola',
      attachments: const <Map<String, Object?>>[
        <String, Object?>{
          'type': 'file',
          'origin': 'attachment',
          'name': 'readme.md',
          'path': '/tmp/readme.md',
        },
      ],
    );
    final fileTurn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(fileTurn.payload['input'], <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': 'config/AGENTS.md hola'},
      <String, Object?>{
        'type': 'text',
        'text': '\n\n/tmp/readme.md',
        'text_elements': <Map<String, Object?>>[
          <String, Object?>{
            'byteRange': <String, Object?>{'start': 2, 'end': 16},
            'placeholder': 'readme.md',
          },
        ],
      },
    ]);
    expect(fileTurn.payload['userMessage'], <String, Object?>{
      'text': 'config/AGENTS.md hola',
      'attachments': <Map<String, Object?>>[
        <String, Object?>{
          'path': '/tmp/readme.md',
          'displayName': 'readme.md',
          'kind': 'file',
          'origin': 'attachment',
          'isImage': false,
          'isDirectory': false,
        },
      ],
    });

    await controller.send(
      'Transcribe this',
      attachments: const <Map<String, Object?>>[
        <String, Object?>{
          'type': 'localAudio',
          'origin': 'attachment',
          'name': 'prompt.wav',
          'path': '/tmp/prompt.wav',
        },
      ],
    );
    final audioTurn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(audioTurn.payload['input'], <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': 'Transcribe this'},
      <String, Object?>{'type': 'localAudio', 'path': '/tmp/prompt.wav'},
    ]);

    await controller.send(
      'Inspect this reference',
      attachments: const <Map<String, Object?>>[
        <String, Object?>{
          'type': 'mention',
          'origin': 'mention',
          'name': 'AGENTS.md',
          'path': 'config/AGENTS.md',
        },
      ],
    );
    final mentionTurn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(mentionTurn.payload['input'], <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': 'Inspect this reference'},
      <String, Object?>{
        'type': 'text',
        'text': '\n\nconfig/AGENTS.md',
        'text_elements': <Map<String, Object?>>[
          <String, Object?>{
            'byteRange': <String, Object?>{'start': 2, 'end': 18},
            'placeholder': 'AGENTS.md',
          },
        ],
      },
    ]);
    expect(mentionTurn.payload['userMessage'], <String, Object?>{
      'text': 'Inspect this reference',
      'attachments': <Map<String, Object?>>[
        <String, Object?>{
          'path': 'config/AGENTS.md',
          'displayName': 'AGENTS.md',
          'kind': 'file',
          'origin': 'mention',
          'isImage': false,
          'isDirectory': false,
        },
      ],
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

    controller.setPlanMode(true);
    await controller.declinePlan();
    final declineTurn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(container.read(provider).value!.planMode, isTrue);
    expect(declineTurn.payload['collaborationMode'], <String, Object?>{
      'mode': 'plan',
      'settings': <String, Object?>{
        'model': 'gpt-current',
        'reasoning_effort': 'low',
      },
    });
    expect((declineTurn.payload['input'] as List).last, <String, Object?>{
      'type': 'text',
      'text': 'Do not implement the plan.',
    });

    await controller.refinePlan('Add tests first');
    final refinementTurn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(container.read(provider).value!.planMode, isTrue);
    expect(
      refinementTurn.payload['collaborationMode'],
      isA<Map<String, Object?>>(),
    );
  });
}
