import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';

class CodexTranscriptStatusWatcher {
  CodexTranscriptStatusWatcher(
    this._statusSink, [
    this._pollInterval = const Duration(milliseconds: 500),
  ]);

  final AgentStatusSink _statusSink;
  final Duration _pollInterval;
  final Map<String, _CodexTranscriptWatch> _watches =
      <String, _CodexTranscriptWatch>{};

  void observeHookEvent(AgentHookEvent event) {
    if (event.agentType != AgentType.codex) {
      return;
    }
    final eventName = _hookEventName(event);
    if (eventName == 'Stop') {
      _watches.remove(event.terminalSessionId)?.dispose();
      return;
    }
    if (eventName != 'UserPromptSubmit') {
      return;
    }

    final transcriptPath = _readString(event.payload, const <String>[
      'transcript_path',
      'transcriptPath',
    ]);
    if (transcriptPath == null) {
      return;
    }

    final previous = _watches.remove(event.terminalSessionId);
    previous?.dispose();
    final watch = _CodexTranscriptWatch(
      statusSink: _statusSink,
      terminalSessionId: event.terminalSessionId,
      workspaceId: event.workspaceId,
      tabId: event.tabId,
      transcriptPath: transcriptPath,
      turnId: _readString(event.payload, const <String>['turn_id', 'turnId']),
      pollInterval: _pollInterval,
    );
    _watches[event.terminalSessionId] = watch;
    watch.start();
  }

  Future<void> scanNowForTesting(String terminalSessionId) async {
    await _watches[terminalSessionId]?.scan();
  }

  void clear() {
    for (final watch in _watches.values) {
      watch.dispose();
    }
    _watches.clear();
  }

  void dispose() {
    clear();
  }
}

class _CodexTranscriptWatch {
  _CodexTranscriptWatch({
    required this._statusSink,
    required this.terminalSessionId,
    required this.workspaceId,
    required this.tabId,
    required this.transcriptPath,
    required this.turnId,
    required this.pollInterval,
  });

  final AgentStatusSink _statusSink;
  final String terminalSessionId;
  final String workspaceId;
  final String tabId;
  final String transcriptPath;
  final String? turnId;
  final Duration pollInterval;
  final Map<String, String> _pendingToolsByCallId = <String, String>{};
  final Set<String> _emittedCallIds = <String>{};
  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _pollTimer;
  var _offset = 0;
  var _partialLine = '';
  var _armed = false;
  var _initialScan = true;
  var _disposed = false;
  var _scanning = false;
  var _scanAgain = false;
  Completer<void>? _activeScan;

  void start() {
    final file = File(transcriptPath);
    try {
      final length = file.existsSync() ? file.lengthSync() : 0;
      _offset = math.max(0, length - _initialTranscriptScanBytes);
      _subscription = file
          .watch(
            events:
                FileSystemEvent.create |
                FileSystemEvent.modify |
                FileSystemEvent.move,
          )
          .listen((_) => _scheduleScan(), onError: (_) {});
    } catch (_) {
      // coverage:ignore-start
      // File watch setup can fail on platform/filesystem races; scan polling
      // still handles the transcript and is covered by watcher tests.
      _offset = 0;
      // coverage:ignore-end
    }
    _pollTimer = Timer.periodic(pollInterval, (_) => _scheduleScan());
    _scheduleScan();
  }

  Future<void> scan() async {
    if (_disposed) {
      return;
    }
    if (_scanning) {
      _scanAgain = true;
      await _activeScan?.future;
      return;
    }
    _scanning = true;
    final activeScan = Completer<void>();
    _activeScan = activeScan;
    try {
      do {
        _scanAgain = false;
        await _scanOnce();
      } while (_scanAgain && !_disposed);
    } finally {
      _scanning = false;
      _activeScan = null;
      activeScan.complete();
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    _pollTimer?.cancel();
    _subscription = null;
    _pollTimer = null;
  }

  void _scheduleScan() {
    unawaited(scan());
  }

  Future<void> _scanOnce() async {
    final file = File(transcriptPath);
    int length;
    try {
      length = await file.length();
    } catch (_) {
      return;
    }
    if (length <= _offset) {
      _finishInitialScanIfNeeded();
      return;
    }

    RandomAccessFile? handle;
    try {
      handle = await file.open();
      await handle.setPosition(_offset);
      final bytes = await handle.read(length - _offset);
      _offset = length;
      final text = _partialLine + utf8.decode(bytes, allowMalformed: true);
      final lines = text.split('\n');
      _partialLine = text.endsWith('\n') ? '' : lines.removeLast();
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) {
          continue;
        }
        _processLine(line);
      }
    } catch (_) {
      return;
    } finally {
      await handle?.close();
      _finishInitialScanIfNeeded();
    }
  }

  void _finishInitialScanIfNeeded() {
    if (!_initialScan) {
      return;
    }
    _initialScan = false;
    _armed = true;
  }

  void _processLine(String line) {
    final record = _jsonObject(line);
    if (record == null) {
      return;
    }
    if (_isCurrentTurnStart(record)) {
      _armed = true;
      return;
    }
    if (!_armed) {
      return;
    }

    final completion = _turnCompletion(record);
    if (completion != null) {
      _emitStop(completion);
      dispose();
      return;
    }

    final pending = _pendingFunctionCall(record);
    if (pending != null) {
      _emitWaiting(pending);
      return;
    }

    final completedCallId = _completedFunctionCallId(record);
    if (completedCallId == null) {
      return;
    }
    final toolName = _pendingToolsByCallId.remove(completedCallId);
    if (toolName == null) {
      return;
    }
    _statusSink.applyHookEvent(
      AgentHookEvent(
        terminalSessionId: terminalSessionId,
        workspaceId: workspaceId,
        tabId: tabId,
        agentType: AgentType.codex,
        hookEventName: 'PostToolUse',
        version: 'codex-transcript',
        payload: <String, Object?>{
          'hook_event_name': 'PostToolUse',
          'tool_name': toolName,
          'tool_use_id': completedCallId,
          'transcript_path': transcriptPath,
        },
      ),
    );
  }

  _TranscriptTurnCompletion? _turnCompletion(Map<String, Object?> record) {
    final payload = _recordPayload(record);
    if (record['type'] != 'event_msg' || payload == null) {
      return null;
    }
    if (turnId != null && payload['turn_id'] != turnId) {
      return null;
    }
    final payloadType = payload['type'];
    if (payloadType == 'task_complete') {
      return _TranscriptTurnCompletion(
        interrupted: false,
        lastAssistantMessage: _string(payload['last_agent_message']),
      );
    }
    if (payloadType == 'turn_aborted') {
      return const _TranscriptTurnCompletion(interrupted: true);
    }
    return null;
  }

  void _emitStop(_TranscriptTurnCompletion completion) {
    _statusSink.applyHookEvent(
      AgentHookEvent(
        terminalSessionId: terminalSessionId,
        workspaceId: workspaceId,
        tabId: tabId,
        agentType: AgentType.codex,
        hookEventName: 'Stop',
        version: 'codex-transcript',
        payload: <String, Object?>{
          'hook_event_name': 'Stop',
          'transcript_path': transcriptPath,
          'is_interrupt': completion.interrupted,
          if (completion.lastAssistantMessage != null)
            'last_assistant_message': completion.lastAssistantMessage,
        },
      ),
    );
  }

  bool _isCurrentTurnStart(Map<String, Object?> record) {
    if (turnId == null) {
      return false;
    }
    final payload = _recordPayload(record);
    if (payload == null) {
      return false;
    }
    return payload['turn_id'] == turnId &&
        (payload['type'] == 'task_started' || record['type'] == 'turn_context');
  }

  _PendingFunctionCall? _pendingFunctionCall(Map<String, Object?> record) {
    final payload = _recordPayload(record);
    if (payload == null) {
      return null;
    }
    final recordType = record['type'];
    final payloadType = payload['type'];
    if (recordType == 'response_item' && payloadType == 'function_call') {
      final toolName = _string(payload['name']);
      if (!_isCodexTranscriptWaitingTool(toolName)) {
        return null;
      }
      final callId = _string(payload['call_id']) ?? _string(payload['id']);
      return _PendingFunctionCall(
        toolName: toolName!,
        callId: callId,
        toolInput: _parseArguments(payload['arguments']),
      );
    }
    if (recordType == 'event_msg' && payloadType == 'request_user_input') {
      return _PendingFunctionCall(
        toolName: 'request_user_input',
        callId: _string(payload['call_id']),
        toolInput: <String, Object?>{'questions': payload['questions']},
      );
    }
    if (recordType == 'event_msg' && payloadType == 'request_permissions') {
      return _PendingFunctionCall(
        toolName: 'request_permissions',
        callId: _string(payload['call_id']),
        toolInput: payload,
      );
    }
    return null;
  }

  String? _completedFunctionCallId(Map<String, Object?> record) {
    final payload = _recordPayload(record);
    if (record['type'] == 'response_item' &&
        payload?['type'] == 'function_call_output') {
      return _string(payload?['call_id']);
    }
    return null;
  }

  void _emitWaiting(_PendingFunctionCall call) {
    final callKey = call.callId ?? '${call.toolName}:${call.toolInput}';
    if (!_emittedCallIds.add(callKey)) {
      return;
    }
    if (call.callId != null) {
      _pendingToolsByCallId[call.callId!] = call.toolName;
    }
    _statusSink.applyHookEvent(
      AgentHookEvent(
        terminalSessionId: terminalSessionId,
        workspaceId: workspaceId,
        tabId: tabId,
        agentType: AgentType.codex,
        hookEventName: 'PreToolUse',
        version: 'codex-transcript',
        payload: <String, Object?>{
          'hook_event_name': 'PreToolUse',
          'tool_name': call.toolName,
          if (call.callId != null) 'tool_use_id': call.callId,
          if (call.toolInput != null) 'tool_input': call.toolInput,
          'transcript_path': transcriptPath,
        },
      ),
    );
  }
}

class _TranscriptTurnCompletion {
  const _TranscriptTurnCompletion({
    required this.interrupted,
    this.lastAssistantMessage,
  });

  final bool interrupted;
  final String? lastAssistantMessage;
}

class _PendingFunctionCall {
  const _PendingFunctionCall({
    required this.toolName,
    required this.callId,
    required this.toolInput,
  });

  final String toolName;
  final String? callId;
  final Object? toolInput;
}

String? _hookEventName(AgentHookEvent event) {
  return event.hookEventName ??
      _readString(event.payload, const <String>[
        'hook_event_name',
        'hookEventName',
      ]);
}

Map<String, Object?>? _recordPayload(Map<String, Object?> record) {
  final payload = record['payload'];
  return payload is Map ? Map<String, Object?>.from(payload) : null;
}

Map<String, Object?>? _jsonObject(String line) {
  try {
    final decoded = jsonDecode(line);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

Object? _parseArguments(Object? arguments) {
  if (arguments is! String) {
    return arguments;
  }
  try {
    final decoded = jsonDecode(arguments);
    return decoded;
  } catch (_) {
    return arguments;
  }
}

String? _readString(Map<String, Object?> payload, List<String> keys) {
  for (final key in keys) {
    final value = _string(payload[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

String? _string(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _isCodexTranscriptWaitingTool(String? toolName) {
  return toolName == 'request_user_input' ||
      toolName == 'functions.request_user_input' ||
      toolName == 'request_permissions' ||
      toolName == 'functions.request_permissions' ||
      toolName == 'request_approval' ||
      toolName == 'functions.request_approval';
}

const int _initialTranscriptScanBytes = 256 * 1024;
