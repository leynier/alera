part of 'codex_transcript_status_watcher.dart';

extension _CodexTranscriptWatchParsing on _CodexTranscriptWatch {
  void _processLine(String line, {required int lifecycleGeneration}) {
    if (!_isCurrentGeneration(lifecycleGeneration)) {
      return;
    }
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
      _emitStop(completion, lifecycleGeneration: lifecycleGeneration);
      dispose();
      return;
    }

    final pending = _pendingFunctionCall(record);
    if (pending != null) {
      _emitWaiting(pending, lifecycleGeneration: lifecycleGeneration);
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
    if (!_isCurrentGeneration(lifecycleGeneration)) {
      return;
    }
    _statusSink.applyHookEvent(
      AgentHookEvent(
        terminalSessionId: terminalSessionId,
        workspaceId: workspaceId,
        tabId: tabId,
        agentType: .codex,
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

  void _emitStop(
    _TranscriptTurnCompletion completion, {
    required int lifecycleGeneration,
  }) {
    if (!_isCurrentGeneration(lifecycleGeneration)) {
      return;
    }
    _statusSink.applyHookEvent(
      AgentHookEvent(
        terminalSessionId: terminalSessionId,
        workspaceId: workspaceId,
        tabId: tabId,
        agentType: .codex,
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

  void _emitWaiting(
    _PendingFunctionCall call, {
    required int lifecycleGeneration,
  }) {
    if (!_isCurrentGeneration(lifecycleGeneration)) {
      return;
    }
    final callKey = call.callId ?? '${call.toolName}:${call.toolInput}';
    if (!_emittedCallIds.add(callKey)) {
      return;
    }
    if (call.callId != null) {
      _pendingToolsByCallId[call.callId!] = call.toolName;
    }
    if (!_isCurrentGeneration(lifecycleGeneration)) {
      return;
    }
    _statusSink.applyHookEvent(
      AgentHookEvent(
        terminalSessionId: terminalSessionId,
        workspaceId: workspaceId,
        tabId: tabId,
        agentType: .codex,
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

class const _TranscriptTurnCompletion({
  required final bool interrupted,
  final String? lastAssistantMessage,
});

class const _PendingFunctionCall({
  required final String toolName,
  required final String? callId,
  required final Object? toolInput,
});

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
