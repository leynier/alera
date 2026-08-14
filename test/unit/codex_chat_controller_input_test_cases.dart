part of 'codex_chat_controller_test.dart';

void registerCodexChatControllerInputTests() {
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
    const legacy = CodexPendingRequest(
      id: 70,
      method: 'execCommandApproval',
      params: <String, Object?>{'command': 'git status'},
    );
    expect(legacy.supportsApprovalDecision('cancel'), isTrue);
    await controller.respondApproval(legacy, decision: 'cancel');
    expect(client.requests.last.payload['result'], <String, Object?>{
      'decision': 'abort',
    });
    await controller.respondApproval(legacy, decision: 'decline');
    expect(client.requests.last.payload['result'], <String, Object?>{
      'decision': 'denied',
    });
    const legacyPatch = CodexPendingRequest(
      id: 72,
      method: 'applyPatchApproval',
      params: <String, Object?>{'path': 'lib/main.dart'},
    );
    await controller.respondApproval(legacyPatch, decision: 'decline');
    expect(client.requests.last.payload['result'], <String, Object?>{
      'decision': 'denied',
    });
    const legacyNetwork = CodexPendingRequest(
      id: 71,
      method: 'execCommandApproval',
      params: <String, Object?>{},
    );
    await controller.respondApproval(
      legacyNetwork,
      decision: const <String, Object?>{
        'applyNetworkPolicyAmendment': <String, Object?>{
          'network_policy_amendment': <String, Object?>{'host': 'example.com'},
        },
      },
    );
    expect(client.requests.last.payload['result'], <String, Object?>{
      'decision': <String, Object?>{
        'network_policy_amendment': <String, Object?>{
          'network_policy_amendment': <String, Object?>{'host': 'example.com'},
        },
      },
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
    const proposed = CodexPendingRequest(
      id: 10,
      method: 'item/commandExecution/requestApproval',
      params: <String, Object?>{
        'proposedExecpolicyAmendment': <Object?>['git', 'status'],
      },
    );
    expect(proposed.supportsApprovalDecision('accept'), isTrue);
    expect(proposed.supportsApprovalDecision('acceptForSession'), isTrue);
    expect(proposed.supportsApprovalDecision('cancel'), isTrue);
    expect(
      proposed.supportsApprovalDecision('acceptWithExecpolicyAmendment'),
      isTrue,
    );
    expect(
      proposed.approvalDecisionValue('acceptWithExecpolicyAmendment'),
      <String, Object?>{
        'acceptWithExecpolicyAmendment': <String, Object?>{
          'execpolicy_amendment': <Object?>['git', 'status'],
        },
      },
    );
    const plainFile = CodexPendingRequest(
      id: 11,
      method: 'item/fileChange/requestApproval',
      params: <String, Object?>{},
    );
    expect(
      plainFile.supportsApprovalDecision('acceptWithExecpolicyAmendment'),
      isFalse,
    );
    expect(
      plainFile.supportsApprovalDecision('applyNetworkPolicyAmendment'),
      isFalse,
    );
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
            'Use these inputs and "docs/my notes.md"',
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
                tokenText: '"docs/my notes.md"',
              ),
            ],
            attachments: const <CodexInputAttachment>[
              CodexInputAttachment(path: '/tmp/image.png', isImage: true),
              CodexInputAttachment(
                path: '/tmp/mentioned-image.png',
                isImage: true,
                origin: CodexInputAttachmentOrigin.mention,
              ),
              CodexInputAttachment(
                path: '/tmp/browser-annotation.png',
                isImage: true,
                annotationContext:
                    'Browser annotation context\nComment: Fix spacing.',
                annotationUrl: 'https://example.com',
                annotationTitle: 'Example',
                annotationCount: 1,
              ),
              CodexInputAttachment(path: '/tmp/prompt.wav', isImage: false),
              CodexInputAttachment(
                path: '/tmp/notes file.txt',
                displayName: 'notes file.txt',
                isImage: false,
              ),
            ],
          );
      final turn = client.requests.lastWhere(
        (request) => request.type == 'codex.turn.start',
      );
      expect(turn.payload['approvalPolicy'], 'on-request');
      expect(turn.payload['approvalsReviewer'], 'user');
      expect(turn.payload['sandboxPolicy'], <String, Object?>{
        'type': 'workspaceWrite',
        'writableRoots': const <String>[],
        'networkAccess': false,
      });
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
          'type': 'text',
          'text': 'Use these inputs and "docs/my notes.md"',
          'text_elements': <Map<String, Object?>>[
            <String, Object?>{
              'byteRange': <String, Object?>{'start': 21, 'end': 39},
              'placeholder': 'my notes.md',
            },
          ],
        },
        <String, Object?>{'type': 'localImage', 'path': '/tmp/image.png'},
        <String, Object?>{
          'type': 'localImage',
          'path': '/tmp/mentioned-image.png',
        },
        <String, Object?>{
          'type': 'localImage',
          'path': '/tmp/browser-annotation.png',
        },
        <String, Object?>{
          'type': 'text',
          'text': 'Browser annotation context\nComment: Fix spacing.',
        },
        <String, Object?>{'type': 'localAudio', 'path': '/tmp/prompt.wav'},
        <String, Object?>{
          'type': 'text',
          'text': '\n\n"/tmp/notes file.txt"',
          'text_elements': <Map<String, Object?>>[
            <String, Object?>{
              'byteRange': <String, Object?>{'start': 2, 'end': 23},
              'placeholder': 'notes file.txt',
            },
          ],
        },
      ]);
      final presentation = Map<String, Object?>.from(
        turn.payload['userMessage']! as Map,
      );
      expect(presentation['text'], 'Use these inputs and "docs/my notes.md"');
      final presentedAttachments = presentation['attachments']! as List;
      expect(presentedAttachments, hasLength(6));
      expect(
        presentedAttachments.map((value) => (value as Map)['path']),
        containsAll(<String>[
          '/tmp/image.png',
          '/tmp/mentioned-image.png',
          '/tmp/browser-annotation.png',
          '/tmp/prompt.wav',
          '/tmp/notes file.txt',
          'docs/my notes.md',
        ]),
      );
      final annotationPresentation =
          presentedAttachments.firstWhere(
                (value) =>
                    (value as Map)['path'] == '/tmp/browser-annotation.png',
              )
              as Map;
      expect(annotationPresentation['annotationUrl'], 'https://example.com');
      expect(annotationPresentation['annotationTitle'], 'Example');
      expect(annotationPresentation['annotationCount'], 1);

      await container
          .read(provider.notifier)
          .send(
            '',
            attachments: const <CodexInputAttachment>[
              CodexInputAttachment(path: '/tmp/only.md', isImage: false),
            ],
          );
      final attachmentOnlyTurn = client.requests.lastWhere(
        (request) => request.type == 'codex.turn.start',
      );
      expect(attachmentOnlyTurn.payload['input'], <Object?>[
        <String, Object?>{
          'type': 'text',
          'text': '/tmp/only.md',
          'text_elements': <Map<String, Object?>>[
            <String, Object?>{
              'byteRange': <String, Object?>{'start': 0, 'end': 12},
              'placeholder': 'only.md',
            },
          ],
        },
      ]);
      expect(attachmentOnlyTurn.payload['userMessage'], <String, Object?>{
        'text': '',
        'attachments': <Map<String, Object?>>[
          <String, Object?>{
            'path': '/tmp/only.md',
            'displayName': 'only.md',
            'kind': 'file',
            'origin': 'attachment',
            'isImage': false,
            'isDirectory': false,
          },
        ],
      });

      await container
          .read(provider.notifier)
          .send(
            'Unicode path',
            attachments: const <CodexInputAttachment>[
              CodexInputAttachment(
                path: '/tmp/á notes.md',
                displayName: 'á notes.md',
                isImage: false,
              ),
            ],
          );
      final unicodeTurn = client.requests.lastWhere(
        (request) => request.type == 'codex.turn.start',
      );
      final reference = (unicodeTurn.payload['input'] as List).last as Map;
      final byteRange =
          ((reference['text_elements'] as List).single as Map)['byteRange']
              as Map;
      expect(reference['text'], '\n\n"/tmp/á notes.md"');
      expect(byteRange['start'], 2);
      expect(byteRange['end'], 2 + utf8.encode('"/tmp/á notes.md"').length);

      await container
          .read(provider.notifier)
          .send(
            'Inspect /tmp/archive',
            attachments: const <CodexInputAttachment>[
              CodexInputAttachment(
                path: '/tmp/a',
                displayName: 'a',
                isImage: false,
              ),
            ],
          );
      final prefixTurn = client.requests.lastWhere(
        (request) => request.type == 'codex.turn.start',
      );
      expect(prefixTurn.payload['input'], <Object?>[
        <String, Object?>{'type': 'text', 'text': 'Inspect /tmp/archive'},
        <String, Object?>{
          'type': 'text',
          'text': '\n\n/tmp/a',
          'text_elements': <Map<String, Object?>>[
            <String, Object?>{
              'byteRange': <String, Object?>{'start': 2, 'end': 8},
              'placeholder': 'a',
            },
          ],
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
    expect(turn.payload['collaborationMode'], <String, Object?>{
      'mode': 'default',
      'settings': <String, Object?>{
        'model': 'gpt-current',
        'reasoning_effort': 'low',
      },
    });
    expect((turn.payload['input'] as List).last, <String, Object?>{
      'type': 'text',
      'text': 'Implement plan',
    });

    controller.setPlanMode(true);
    await controller.declinePlan();
    turn = client.requests.lastWhere(
      (request) => request.type == 'codex.turn.start',
    );
    expect(container.read(provider).planMode, isTrue);
    expect(turn.payload['collaborationMode'], <String, Object?>{
      'mode': 'plan',
      'settings': <String, Object?>{
        'model': 'gpt-current',
        'reasoning_effort': 'low',
      },
    });
    expect((turn.payload['input'] as List).last, <String, Object?>{
      'type': 'text',
      'text': 'Do not implement the plan.',
    });

    await controller.refinePlan('Add tests first');
    turn = client.requests.lastWhere(
      (request) => request.type == 'codex.turn.start',
    );
    expect(container.read(provider).planMode, isTrue);
    expect(turn.payload['collaborationMode'], <String, Object?>{
      'mode': 'plan',
      'settings': <String, Object?>{
        'model': 'gpt-current',
        'reasoning_effort': 'low',
      },
    });
  });
}
