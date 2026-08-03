import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_codex_controller.g.dart';

@riverpod
class MobileCodexController extends _$MobileCodexController {
  MobileCodexClient? _client;
  StreamSubscription<MobileRuntimeEvent>? _events;

  @override
  Future<MobileCodexState> build(String hostId, String tabId) async {
    final client = await ref.watch(
      hostConnectionControllerProvider(hostId).future,
    );
    if (!client.supportsCodexChat) {
      throw UnsupportedError('This runtime host does not support Codex chat.');
    }
    _client = client;
    _events = client.events.listen(_onEvent);
    ref.onDispose(() => _events?.cancel());
    final response = await client.codexRequest(
      'codex.thread.open',
      <String, Object?>{'tabId': tabId},
    );
    final snapshot = MobileCodexState.fromSnapshot(response['snapshot']);
    try {
      final models = await client.codexRequest('codex.model.list');
      return snapshot.copyWith(models: _modelItems(models));
    } catch (_) {
      return snapshot;
    }
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final client = _client;
    if (client == null) return;
    final current = state.value;
    if (current?.busy == true) return;
    state = AsyncData(
      current?.copyWith(sending: true, error: null) ??
          const MobileCodexState(sending: true),
    );
    try {
      await client.codexRequest('codex.turn.start', <String, Object?>{
        'tabId': tabId,
        'input': <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': trimmed},
        ],
        'approvalPolicy': 'on-request',
      });
      if (ref.mounted) {
        final current = state.value;
        if (current != null) {
          state = AsyncData(current.copyWith(sending: false));
        }
      }
    } catch (error, stackTrace) {
      if (ref.mounted) {
        state = AsyncData(
          (state.value ?? const MobileCodexState()).copyWith(
            sending: false,
            error: error.toString(),
          ),
        );
      } else {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  Future<void> stop() async {
    final client = _client;
    final active = state.value?.activeTurnId;
    if (client == null || active == null) return;
    try {
      await client.codexRequest('codex.turn.interrupt', <String, Object?>{
        'tabId': tabId,
        'turnId': active,
      });
    } catch (error) {
      state = AsyncData(
        (state.value ?? const MobileCodexState()).copyWith(
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> respond(Map<String, Object?> request, bool accepted) async {
    final client = _client;
    if (client == null) return;
    await client.codexRequest('codex.response', <String, Object?>{
      'requestId': request['id'],
      'result': <String, Object?>{'decision': accepted ? 'accept' : 'decline'},
    });
  }

  void _onEvent(MobileRuntimeEvent event) {
    if (event.name != 'codexThreadChanged' || event.payload['tabId'] != tabId) {
      return;
    }
    final next = MobileCodexState.fromSnapshot(event.payload['snapshot']);
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        next.copyWith(
          models: current.models,
          sending: next.busy ? current.sending : false,
        ),
      );
    }
  }
}

List<Map<String, Object?>> _modelItems(Map<String, Object?> payload) {
  final items = payload['data'] ?? payload['items'];
  if (items is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final item in items)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}
