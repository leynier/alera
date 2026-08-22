part of '../mobile_codex_chat_test.dart';

final class _FakeMobileCodexClient implements MobileCodexClient {
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();
  final List<_Call> calls = <_Call>[];

  @override
  bool get supportsCodexChat => true;
  @override
  bool get supportsCodexGoals => false;

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
