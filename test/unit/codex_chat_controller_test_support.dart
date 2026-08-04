part of 'codex_chat_controller_test.dart';

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

final class _FakeCodexRuntimeClient implements RuntimeHostClient {
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();
  final List<_Request> requests = <_Request>[];
  Map<String, Object?> skills = <String, Object?>{
    'data': <Object?>[
      <String, Object?>{'name': 'review', 'path': '/skills/review'},
    ],
  };

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
        return skills;
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
