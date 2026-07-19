import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_status_host_forwarder.g.dart';

/// Forwards agent status transitions to the runtime-host so it can run
/// push-on-idle orchestration message delivery and resolve @agent groups.
/// The host keys presence by terminal session id, which doubles as the
/// orchestration terminal handle.
@Riverpod(keepAlive: true)
AgentStatusHostForwarder agentStatusHostForwarder(Ref ref) {
  final forwarder = AgentStatusHostForwarder(
    client: ref.watch(runtimeHostClientProvider),
  );
  ref.listen<Map<String, AgentStatusEntry>>(
    agentStatusControllerProvider,
    (previous, next) => forwarder.onStatusChanged(previous, next),
    fireImmediately: true,
  );
  ref.onDispose(forwarder.dispose);
  return forwarder;
}

class AgentStatusHostForwarder {
  AgentStatusHostForwarder({
    required this.client,
    this.debounce = const Duration(milliseconds: 100),
  }) {
    _runtimeEventSub = client.runtimeEvents.listen((event) {
      if (event.name == aleraRuntimeHostConnectedEvent) {
        replayPresenceSnapshot();
      }
    });
  }

  final RuntimeHostClient client;
  final Duration debounce;

  final Map<String, Map<String, Object?>> _pending =
      <String, Map<String, Object?>>{};
  Map<String, AgentStatusEntry> _lastSeen = const <String, AgentStatusEntry>{};
  late final StreamSubscription<RuntimeHostEvent> _runtimeEventSub;
  Timer? _timer;
  bool _disposed = false;

  void onStatusChanged(
    Map<String, AgentStatusEntry>? previous,
    Map<String, AgentStatusEntry> next,
  ) {
    if (_disposed) {
      return;
    }
    final before = previous ?? _lastSeen;
    for (final entry in next.values) {
      final prior = before[entry.terminalSessionId];
      if (prior != null &&
          prior.state == entry.state &&
          prior.agentType == entry.agentType) {
        continue;
      }
      _pending[entry.terminalSessionId] = <String, Object?>{
        'terminalSessionId': entry.terminalSessionId,
        'workspaceId': entry.workspaceId,
        'tabId': entry.tabId,
        'agentType': entry.agentType.key,
        'state': entry.state.key,
        'stateStartedAt': entry.stateStartedAt.toUtc().toIso8601String(),
      };
    }
    for (final sessionId in before.keys) {
      if (!next.containsKey(sessionId)) {
        _pending[sessionId] = <String, Object?>{
          'terminalSessionId': sessionId,
          'removed': true,
        };
      }
    }
    _lastSeen = next;
    if (_pending.isEmpty) {
      return;
    }
    _timer ??= Timer(debounce, _flush);
  }

  void replayPresenceSnapshot() {
    if (_disposed || _lastSeen.isEmpty) {
      return;
    }
    for (final entry in _lastSeen.values) {
      _pending[entry.terminalSessionId] = <String, Object?>{
        'terminalSessionId': entry.terminalSessionId,
        'workspaceId': entry.workspaceId,
        'tabId': entry.tabId,
        'agentType': entry.agentType.key,
        'state': entry.state.key,
        'stateStartedAt': entry.stateStartedAt.toUtc().toIso8601String(),
      };
    }
    _timer ??= Timer(debounce, _flush);
  }

  void _flush() {
    _timer = null;
    if (_disposed || _pending.isEmpty) {
      return;
    }
    final entries = _pending.values.toList(growable: false);
    _pending.clear();
    unawaited(
      client
          .runtimeRequest('orchestration.agentStatus', <String, Object?>{
            'entries': entries,
          })
          .then<void>(
            (_) {},
            onError: (Object error) {
              if (!_isPermanentOrchestrationCapabilityError(error)) {
                _retry(entries);
              }
            },
          ),
    );
  }

  void _retry(List<Map<String, Object?>> entries) {
    if (_disposed) {
      return;
    }
    for (final entry in entries) {
      final sessionId = entry['terminalSessionId'];
      if (sessionId is String &&
          sessionId.isNotEmpty &&
          _retryEntryIsFresh(sessionId, entry)) {
        _pending.putIfAbsent(sessionId, () => entry);
      }
    }
    if (_pending.isNotEmpty) {
      _timer ??= Timer(_retryDelay, _flush);
    }
  }

  bool _retryEntryIsFresh(String sessionId, Map<String, Object?> entry) {
    final current = _lastSeen[sessionId];
    if (entry['removed'] == true) {
      return current == null;
    }
    if (current == null) {
      return false;
    }
    return entry['state'] == current.state.key &&
        entry['agentType'] == current.agentType.key &&
        entry['workspaceId'] == current.workspaceId &&
        entry['tabId'] == current.tabId;
  }

  Duration get _retryDelay =>
      debounce == Duration.zero ? const Duration(milliseconds: 1) : debounce;

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_runtimeEventSub.cancel());
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}

bool _isPermanentOrchestrationCapabilityError(Object error) {
  final message = error is StateError ? error.message : error.toString();
  return message.contains('does not support orchestration') &&
      message.contains('Restart Alera');
}
