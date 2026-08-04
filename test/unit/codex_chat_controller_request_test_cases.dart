part of 'codex_chat_controller_test.dart';

void registerCodexChatControllerRequestTests() {
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
