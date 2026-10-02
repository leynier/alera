import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:alera/src/features/agent_status/infra/codex_transcript_status_watcher.dart';
import 'package:alera/src/rust/api/agent_hooks.dart' as rust_hooks;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef ApplicationSupportDirectoryResolver = Future<Directory> Function();
typedef AgentHookEnabledPredicate = bool Function(AgentType agentType);

class AgentHookReceiver._(
  final AgentStatusSink _statusSink,
  final ApplicationSupportDirectoryResolver _applicationSupportDirectory,
  final String _token,
  final AgentHookEnabledPredicate _isAgentEnabled,
  CodexTranscriptStatusWatcher? codexTranscriptStatusWatcher,
  final AgentHookServer _hookServer,
) {
  factory({
    required AgentStatusSink statusSink,
    ApplicationSupportDirectoryResolver? applicationSupportDirectory,
    String? token,
    AgentHookEnabledPredicate? isAgentEnabled,
    CodexTranscriptStatusWatcher? codexTranscriptStatusWatcher,
    AgentHookServer? hookServer,
  }) {
    return AgentHookReceiver._(
      statusSink,
      applicationSupportDirectory ?? getApplicationSupportDirectory,
      token ?? createAgentHookToken(),
      isAgentEnabled ?? ((_) => true),
      codexTranscriptStatusWatcher,
      hookServer ?? RustAgentHookServer(),
    );
  }

  this
    : _codexTranscriptStatusWatcher =
          codexTranscriptStatusWatcher ??
          CodexTranscriptStatusWatcher(_statusSink);

  final CodexTranscriptStatusWatcher _codexTranscriptStatusWatcher;

  Future<void> _lifecycle = Future<void>.value();
  AgentHookEndpoint? _endpoint;
  StreamSubscription<AgentHookEventBatch>? _eventSubscription;
  var _eventGeneration = 0;
  bool _disposed = false;

  bool get isRunning => _endpoint != null;

  AgentHookEndpoint? get endpoint => _endpoint;

  Future<void> start() {
    if (_disposed) {
      throw StateError('Agent hook receiver is disposed.');
    }
    return _enqueueLifecycle(() async {
      if (_disposed || _endpoint != null) {
        return;
      }
      await _start();
    });
  }

  Future<void> updateEnabledAgents() {
    return _enqueueLifecycle(() async {
      if (_disposed || _endpoint == null) {
        return;
      }
      await _hookServer.setEnabledAgents(_enabledAgentKeys());
    });
  }

  Future<void> stop() {
    return _enqueueLifecycle(_stop);
  }

  /// Releases per-terminal watch state once the terminal session is gone.
  void clearTerminalSession(String terminalSessionId) {
    _codexTranscriptStatusWatcher.clearTerminal(terminalSessionId);
  }

  Future<Map<String, String>?> launchEnvironmentFor({
    required String terminalSessionId,
    required String workspaceId,
    required String tabId,
  }) async {
    await start();
    return _endpoint?.launchEnvironment(
      terminalSessionId: terminalSessionId,
      workspaceId: workspaceId,
      tabId: tabId,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    _codexTranscriptStatusWatcher.dispose();
  }

  Future<void> _enqueueLifecycle(Future<void> Function() operation) {
    final next = _lifecycle.then<void>((_) => operation());
    // Keep the queue usable after a failed start while returning the original
    // error to the caller that requested the operation.
    _lifecycle = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _stop() async {
    final shouldStopServer = _endpoint != null || _eventSubscription != null;
    final eventSubscription = _eventSubscription;
    _endpoint = null;
    _eventGeneration++;
    _codexTranscriptStatusWatcher.clear();
    _eventSubscription = null;

    Object? firstError;
    StackTrace? firstStackTrace;
    if (shouldStopServer) {
      try {
        // The native producer owns the FRB stream sink. Stop it first so that
        // cancelling the Dart subscription cannot wait for a sink that is
        // still receiving events.
        await _hookServer.stop();
      } catch (error, stackTrace) {
        firstError = error;
        firstStackTrace = stackTrace;
      }
    }
    try {
      await eventSubscription?.cancel();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(
        firstError,
        firstStackTrace ?? StackTrace.current,
      );
    }
  }

  Future<void> _start() async {
    int? startedPort;
    final eventGeneration = ++_eventGeneration;
    try {
      _ensureEventSubscription(eventGeneration);
      startedPort = await _hookServer.start(
        token: _token,
        enabledAgents: _enabledAgentKeys(),
      );
      final supportDir = await _applicationSupportDirectory();
      final endpointDir = Directory(p.join(supportDir.path, 'agent-hooks'));
      final kind = currentAgentHookEndpointFileKind();
      final endpointPath = p.join(
        endpointDir.path,
        agentHookEndpointFileName(kind: kind),
      );
      await writeAgentHookEndpointFile(
        directory: endpointDir,
        filePath: endpointPath,
        kind: kind,
        port: startedPort,
        token: _token,
      );
      _endpoint = AgentHookEndpoint(
        filePath: endpointPath,
        port: startedPort,
        token: _token,
        version: aleraAgentHookProtocolVersion,
      );
    } catch (_) {
      if (startedPort != null) {
        try {
          await _hookServer.stop();
        } catch (_) {
          // Preserve the startup failure and let the next lifecycle operation
          // attempt a fresh server start.
        }
      }
      _eventGeneration++;
      try {
        await _eventSubscription?.cancel();
      } catch (_) {
        // A failed stream cancellation must not leave the lifecycle queue
        // pointing at the failed subscription.
      }
      _eventSubscription = null;
      rethrow;
    }
  }

  void _ensureEventSubscription(int eventGeneration) {
    _eventSubscription = _hookServer.watchEventBatches().listen((batch) {
      if (_disposed || eventGeneration != _eventGeneration) {
        return;
      }
      _handleEventBatch(batch);
    }, onError: (_) {});
  }

  void _handleEventBatch(AgentHookEventBatch batch) {
    try {
      final events = batch.events;
      if (events.isEmpty) {
        return;
      }
      final statusSink = _statusSink;
      if (statusSink is AgentStatusController) {
        statusSink.applyHookEvents(events);
      } else {
        for (final event in events) {
          statusSink.applyHookEvent(event);
        }
      }
      for (final event in events) {
        _codexTranscriptStatusWatcher.observeHookEvent(event);
      }
    } catch (_) {
      return;
    }
  }

  List<String> _enabledAgentKeys() {
    return <String>[
      for (final agentType in AgentType.values)
        if (_isAgentEnabled(agentType)) agentType.key,
    ];
  }
}

class const AgentHookEventBatch({
  required final List<AgentHookEvent> events,
  final int coalescedIntermediateCount = 0,
});

abstract interface class AgentHookServer {
  Stream<AgentHookEventBatch> watchEventBatches();

  Future<int> start({
    required String token,
    required List<String> enabledAgents,
  });

  Future<void> setEnabledAgents(List<String> enabledAgents);

  Future<void> stop();
}

class RustAgentHookServer implements AgentHookServer {
  @override
  Stream<AgentHookEventBatch> watchEventBatches() {
    return rust_hooks.watchAgentHookEventBatches().map((batch) {
      return AgentHookEventBatch(
        events: <AgentHookEvent>[
          for (final dto in batch.events) ?_eventFromDto(dto),
        ],
        coalescedIntermediateCount: batch.coalescedIntermediateCount,
      );
    });
  }

  @override
  Future<int> start({
    required String token,
    required List<String> enabledAgents,
  }) async {
    final endpoint = await rust_hooks.startAgentHookReceiver(
      token: token,
      enabledAgents: enabledAgents,
    );
    return endpoint.port;
  }

  @override
  Future<void> setEnabledAgents(List<String> enabledAgents) {
    return rust_hooks.setAgentHookEnabledAgents(enabledAgents: enabledAgents);
  }

  @override
  Future<void> stop() {
    return rust_hooks.stopAgentHookReceiver();
  }

  AgentHookEvent? _eventFromDto(rust_hooks.AgentHookEventDto dto) {
    final agentType = _agentTypeFromKey(dto.agentType);
    if (agentType == null) {
      return null;
    }
    final decoded = jsonDecode(dto.payloadJson);
    if (decoded is! Map) {
      return null;
    }
    return AgentHookEvent(
      terminalSessionId: dto.terminalSessionId,
      workspaceId: dto.workspaceId,
      tabId: dto.tabId,
      agentType: agentType,
      payload: Map<String, Object?>.from(decoded),
      hookEventName: dto.hookEventName,
      version: dto.version,
    );
  }

  AgentType? _agentTypeFromKey(String key) {
    for (final type in AgentType.values) {
      if (type.key == key) {
        return type;
      }
    }
    return null;
  }
}
