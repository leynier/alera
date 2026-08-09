part of 'codex_chat_controller_test.dart';

void registerCodexChatControllerRequestTests() {
  test('serializes every commit review field for the app server', () async {
    final client = _FakeCodexRuntimeClient();
    addTearDown(client.dispose);
    final host = CodexChatHostClient(client);

    await host.review(
      'tab-review',
      target: 'commit',
      argument: 'abc1234',
      commitTitle: 'Fix the parser',
      delivery: 'detached',
    );

    final request = client.requests.singleWhere(
      (request) => request.type == 'codex.review.start',
    );
    expect(request.payload, <String, Object?>{
      'tabId': 'tab-review',
      'target': <String, Object?>{
        'type': 'commit',
        'sha': 'abc1234',
        'title': 'Fix the parser',
      },
      'delivery': 'detached',
    });
  });

  test('retries capability discovery after a transient failure', () async {
    var statusAttempts = 0;
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) {
        if (type != 'status.get') return null;
        statusAttempts += 1;
        if (statusAttempts == 1) {
          return Future<Object?>.error(StateError('host is starting'));
        }
        return Future<Object?>.value(<String, Object?>{
          'runtimeCapabilities': <String>[
            aleraRuntimeHostCodexSessionsCapability,
          ],
        });
      },
    );
    addTearDown(client.dispose);
    final host = CodexChatHostClient(client);

    expect(await host.supportsSessions(), isFalse);
    expect(await host.supportsSessions(), isTrue);
    expect(statusAttempts, 2);
  });

  test(
    'controller retries session capability discovery after a transient failure',
    () async {
      var statusAttempts = 0;
      final client = _FakeCodexRuntimeClient(
        requestHandler: (type, payload) {
          if (type != 'status.get') return null;
          statusAttempts += 1;
          if (statusAttempts == 1) {
            return Future<Object?>.error(StateError('host is starting'));
          }
          return Future<Object?>.value(<String, Object?>{
            'runtimeCapabilities': <String>[
              aleraRuntimeHostCodexSessionsCapability,
            ],
          });
        },
      );
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
      final provider = codexChatControllerProvider('tab-capability-retry');
      final listener = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listener.close);

      await _settle();

      expect(container.read(provider).supportsSessions, isTrue);
      expect(container.read(provider).error, isNull);
      expect(statusAttempts, 2);
    },
  );

  test('retries capability discovery before applying turn policy', () async {
    var statusAttempts = 0;
    final client = _FakeCodexRuntimeClient(
      requestHandler: (type, payload) {
        if (type != 'status.get') return null;
        statusAttempts += 1;
        if (statusAttempts == 1) {
          return Future<Object?>.error(StateError('host is starting'));
        }
        return Future<Object?>.value(<String, Object?>{
          'runtimeCapabilities': <String>[
            aleraRuntimeHostCodexTurnPolicyCapability,
          ],
        });
      },
    );
    addTearDown(client.dispose);
    final host = CodexChatHostClient(client);

    await host.startTurn(
      'tab-turn-policy-retry',
      const <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': 'Inspect'},
      ],
      expectedThreadId: null,
      userMessage: const <String, Object?>{'text': 'Inspect'},
      reasoningEffort: 'medium',
      speedMode: 'standard',
      permissionMode: 'auto-review',
      planMode: false,
    );

    final turn = client.requests.singleWhere(
      (request) => request.type == 'codex.turn.start',
    );
    expect(statusAttempts, 2);
    expect(turn.payload['approvalPolicy'], 'on-request');
    expect(turn.payload['approvalsReviewer'], 'auto_review');
    expect(turn.payload, contains('sandboxPolicy'));
  });

  test(
    'maps approval modes to current app-server fields without weakening legacy values',
    () async {
      final client = _FakeCodexRuntimeClient();
      addTearDown(client.dispose);
      final host = CodexChatHostClient(client);

      for (final mode in <String>[
        'untrusted',
        'on-request',
        'auto-review',
        'never',
      ]) {
        await host.startTurn(
          'tab-1',
          const <Map<String, Object?>>[
            <String, Object?>{'type': 'text', 'text': 'Inspect'},
          ],
          expectedThreadId: null,
          userMessage: const <String, Object?>{'text': 'Inspect'},
          reasoningEffort: 'medium',
          speedMode: 'standard',
          permissionMode: mode,
          planMode: false,
        );
      }

      final turns = client.requests
          .where((request) => request.type == 'codex.turn.start')
          .toList(growable: false);
      expect(turns[0].payload['approvalPolicy'], 'untrusted');
      expect(turns[0].payload['approvalsReviewer'], 'user');
      expect(turns[0].payload['sandboxPolicy'], <String, Object?>{
        'type': 'workspaceWrite',
        'writableRoots': const <String>[],
        'networkAccess': false,
      });
      expect(turns[1].payload['approvalPolicy'], 'on-request');
      expect(turns[1].payload['approvalsReviewer'], 'user');
      expect(turns[2].payload['approvalPolicy'], 'on-request');
      expect(turns[2].payload['approvalsReviewer'], 'auto_review');
      expect(turns[3].payload['approvalPolicy'], 'never');
      expect(turns[3].payload['approvalsReviewer'], 'user');
      expect(turns[3].payload['sandboxPolicy'], <String, Object?>{
        'type': 'dangerFullAccess',
      });
      for (final turn in turns) {
        expect(turn.payload['collaborationMode'], <String, Object?>{
          'mode': 'default',
          'settings': <String, Object?>{'reasoning_effort': 'medium'},
        });
      }
    },
  );

  test('preserves legacy permission modes for an older sidecar', () async {
    final client = _FakeCodexRuntimeClient(
      runtimeCapabilities: const <String>[],
    );
    addTearDown(client.dispose);
    final host = CodexChatHostClient(client);

    for (final mode in <String>[
      'untrusted',
      'on-request',
      'auto-review',
      'never',
    ]) {
      await host.startTurn(
        'tab-1',
        const <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': 'Inspect'},
        ],
        expectedThreadId: null,
        userMessage: const <String, Object?>{'text': 'Inspect'},
        reasoningEffort: 'medium',
        speedMode: 'standard',
        permissionMode: mode,
        planMode: false,
      );
    }

    final turns = client.requests
        .where((request) => request.type == 'codex.turn.start')
        .toList(growable: false);
    expect(turns.map((turn) => turn.payload['approvalPolicy']), <String>[
      'untrusted',
      'on-request',
      'on-request',
      'never',
    ]);
    for (final turn in turns) {
      expect(turn.payload, isNot(contains('approvalsReviewer')));
      expect(turn.payload, isNot(contains('sandboxPolicy')));
    }
    expect(
      turns[2].payload['configuration'],
      containsPair('permissionMode', 'on-request'),
    );
  });

  test('uses current questions, permissions and elicitations', () async {
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
        'isBlocking': false,
        'questions': <Object?>[
          <String, Object?>{'id': 'mode', 'question': 'Choose'},
        ],
      },
    );
    await controller.snoozeQuestionAutoResolution(question);
    expect(client.requests.last.type, 'codex.request.snooze');
    expect(client.requests.last.payload, <String, Object?>{'requestId': 8});
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
    await controller.respondApproval(permissions, decision: 'accept');
    expect(client.requests.last.payload['result'], <String, Object?>{
      'permissions': <String, Object?>{
        'fileSystem': <String, Object?>{'read': true, 'write': false},
        'network': <String, Object?>{'enabled': true},
      },
      'scope': 'turn',
    });
    await controller.respondApproval(permissions, decision: 'decline');
    expect(client.requests.last.payload['result'], <String, Object?>{
      'permissions': <String, Object?>{},
      'scope': 'turn',
    });
    const elicitation = CodexPendingRequest(
      id: 10,
      method: 'mcpServer/elicitation/request',
      params: <String, Object?>{
        'mode': 'form',
        'requestedSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'repository': <String, Object?>{'type': 'string'},
          },
        },
      },
    );
    expect(elicitation.hasSupportedElicitationForm, isTrue);
    await controller.respondElicitation(
      elicitation,
      action: 'accept',
      content: <String, Object?>{'repository': 'alera'},
    );
    expect(client.requests.last.payload['result'], <String, Object?>{
      'action': 'accept',
      'content': <String, Object?>{'repository': 'alera'},
    });
  });
}
