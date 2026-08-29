part of 'codex_transcript_status_watcher.dart';

class _CodexTranscriptWatch {
  _CodexTranscriptWatch({
    required this._statusSink,
    required this.terminalSessionId,
    required this.workspaceId,
    required this.tabId,
    required this.transcriptPath,
    required this.turnId,
    required this.watchdogInterval,
    required this.appForeground,
  });

  final AgentStatusSink _statusSink;
  final String terminalSessionId;
  final String workspaceId;
  final String tabId;
  final String transcriptPath;
  final String? turnId;
  final Duration watchdogInterval;
  final AppForeground appForeground;
  final Map<String, String> _pendingToolsByCallId = <String, String>{};
  final Set<String> _emittedCallIds = <String>{};
  StreamSubscription<FileSystemEvent>? _subscription;
  StreamSubscription<bool>? _foregroundSubscription;
  Timer? _watchdogTimer;
  Timer? _pollTimer;

  /// Whether polling was the active strategy when the app went to the
  /// background, so returning restores the same one rather than upgrading a
  /// degraded watch back to a file-event watch that already failed.
  var _polling = false;
  var _offset = 0;
  var _partialLine = '';
  var _armed = false;
  var _initialScan = true;
  var _disposed = false;
  var _scanning = false;
  var _scanAgain = false;
  Completer<void>? _activeScan;

  void start() {
    _foregroundSubscription = appForeground.changes.listen(_applyForeground);
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
          .listen(
            (_) {
              _armWatchdog();
              _scheduleScan();
            },
            onError: (_) => _enablePolling(),
            onDone: _enablePolling,
          );
      _armWatchdog();
    } catch (_) {
      // coverage:ignore-start
      // File watch setup can fail on platform/filesystem races; scan polling
      // still handles the transcript and is covered by watcher tests.
      _offset = 0;
      _enablePolling();
      // coverage:ignore-end
    }
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
    unawaited(_foregroundSubscription?.cancel());
    _watchdogTimer?.cancel();
    _pollTimer?.cancel();
    _subscription = null;
    _foregroundSubscription = null;
    _watchdogTimer = null;
    _pollTimer = null;
  }

  /// Park the timers while the app is hidden, and catch up on return.
  ///
  /// This is the one poller in the app that scales with how many agents are
  /// running: a stat plus an incremental read per transcript, every interval,
  /// whether or not anyone can see the status it produces.
  ///
  /// The file watch keeps running while parked. It is event driven, so it costs
  /// nothing idle, and leaving it subscribed means a transcript that changes
  /// while hidden is still noticed. Only the safety net stops. Nothing is lost
  /// either way: scanning resumes from the same byte offset, so returning to
  /// the foreground reads whatever accumulated.
  void _applyForeground(bool isForeground) {
    if (_disposed) {
      return;
    }
    if (!isForeground) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    if (_polling) {
      _startPollTimer();
    } else {
      _armWatchdog();
    }
    _scheduleScan();
  }

  void _scheduleScan() {
    unawaited(scan());
  }

  void _armWatchdog() {
    if (_disposed || _polling || !appForeground.isForeground) {
      return;
    }
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(watchdogInterval, () {
      _scheduleScan();
      _armWatchdog();
    });
  }

  void _enablePolling() {
    if (_disposed || _polling) {
      return;
    }
    _polling = true;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _startPollTimer();
  }

  void _startPollTimer() {
    if (_disposed || _pollTimer != null || !appForeground.isForeground) {
      return;
    }
    _pollTimer = Timer.periodic(watchdogInterval, (_) => _scheduleScan());
  }

  Future<void> _scanOnce() async {
    if (!_pollingScanAllowed) {
      return;
    }
    final file = File(transcriptPath);
    int length;
    try {
      length = await file.length();
    } catch (_) {
      return;
    }
    if (!_pollingScanAllowed) {
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
      if (!_pollingScanAllowed) {
        return;
      }
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

  bool get _pollingScanAllowed =>
      !_disposed && (!_polling || appForeground.isForeground);

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
