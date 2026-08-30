part of 'codex_chat_controller_test.dart';

Future<void> _settle() async {
  await Future<void>.delayed(.zero);
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

final class _FakeCodexRuntimeClient({
  final List<String> runtimeCapabilities = const <String>[
    aleraRuntimeHostCodexSessionsCapability,
    aleraRuntimeHostCodexTurnPolicyCapability,
  ],
  final Future<Object?>? Function(String type, Map<String, Object?> payload)?
  requestHandler,
}) implements RuntimeHostClient {
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();
  final List<_Request> requests = <_Request>[];
  final Map<String, Map<String, Object?>> configurations =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> recoveries =
      <String, Map<String, Object?>>{};
  Map<String, Object?> skills = <String, Object?>{
    'data': <Object?>[
      <String, Object?>{'name': 'review', 'path': '/skills/review'},
    ],
  };
  Map<String, Object?>? openSnapshot;
  String? openThreadId;
  Map<String, Object?>? historyResponse;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add(_Request(type, payload));
    final handled = requestHandler?.call(type, payload);
    if (handled != null) return handled;
    switch (type) {
      case 'status.get':
        return <String, Object?>{'runtimeCapabilities': runtimeCapabilities};
      case 'codex.thread.open':
        final tabId = payload['tabId']! as String;
        return <String, Object?>{
          'threadId': openThreadId,
          'snapshot':
              openSnapshot ??
              <String, Object?>{
                'events': const <Object?>[],
                'timelineCells': const <Object?>[],
                'pendingRequests': const <Object?>[],
              },
          'configuration': configurations[tabId],
          'recovery': recoveries[tabId],
        };
      case 'codex.thread.history':
        return historyResponse ?? const <String, Object?>{};
      case 'codex.tab.configure':
        final tabId = payload['tabId']! as String;
        configurations[tabId] = Map<String, Object?>.from(
          payload['configuration']! as Map,
        );
        return <String, Object?>{
          'tabId': tabId,
          'configuration': configurations[tabId],
        };
      case 'codex.thread.recover':
        final tabId = payload['tabId']! as String;
        recoveries.remove(tabId);
        return <String, Object?>{
          'threadId': null,
          'snapshot': <String, Object?>{
            'events': const <Object?>[],
            'timelineCells': const <Object?>[],
            'pendingRequests': const <Object?>[],
          },
          'configuration': configurations[tabId],
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

final class _AutoReviewTestSettingsController extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults.copyWith(
    codexChat: AleraSettings.defaults.codexChat.copyWith(
      permissionMode: 'auto-review',
    ),
  );

  @override
  Future<void> updateCodexChat(CodexChatSettings settings) async {
    state = state.copyWith(codexChat: settings);
  }
}

final class const _Request(
  final String type,
  final Map<String, Object?> payload,
);
