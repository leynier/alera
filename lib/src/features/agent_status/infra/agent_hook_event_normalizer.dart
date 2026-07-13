import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';

part 'normalizers/agy_agent_hook_normalizer.dart';
part 'normalizers/amp_agent_hook_normalizer.dart';
part 'normalizers/claude_agent_hook_normalizer.dart';
part 'normalizers/codex_agent_hook_normalizer.dart';
part 'normalizers/copilot_agent_hook_normalizer.dart';
part 'normalizers/cursor_agent_hook_normalizer.dart';
part 'normalizers/grok_agent_hook_normalizer.dart';
part 'normalizers/opencode_agent_hook_normalizer.dart';
part 'normalizers/pi_agent_hook_normalizer.dart';
part 'normalizers/agent_hook_tool_snapshot.dart';
part 'normalizers/agent_hook_tool_preview.dart';
part 'normalizers/agent_hook_transcript_reader.dart';
part 'normalizers/agent_hook_status_helpers.dart';

class NormalizedAgentStatus {
  const NormalizedAgentStatus({
    required this.state,
    required this.prompt,
    this.toolName,
    this.toolInput,
    this.lastAssistantMessage,
    this.interrupted,
  });

  final AgentStatusState state;
  final String prompt;
  final String? toolName;
  final String? toolInput;
  final String? lastAssistantMessage;
  final bool? interrupted;
}

NormalizedAgentStatus? normalizeAgentHookEvent(
  AgentHookEvent event, {
  AgentStatusEntry? previous,
}) {
  final eventName = agentHookEventName(event);
  if (eventName == null) {
    return null;
  }
  final toolSnapshot = _extractToolSnapshot(event, eventName: eventName);
  final state = switch (event.agentType) {
    AgentType.codex => _normalizeCodexState(eventName, toolSnapshot.toolName),
    AgentType.claude => _normalizeClaudeState(eventName, toolSnapshot.toolName),
    AgentType.copilot => _normalizeCopilotState(
      eventName,
      event.payload,
      toolSnapshot.toolName,
    ),
    AgentType.cursor => _normalizeCursorState(eventName, previous),
    AgentType.agy => _normalizeAgyState(
      eventName,
      toolSnapshot.toolName,
      event.payload,
    ),
    AgentType.opencode => _normalizeOpenCodeState(eventName),
    AgentType.pi => _normalizePiState(eventName),
    AgentType.amp => _normalizeAmpState(eventName),
    AgentType.grok => _normalizeGrokState(eventName, event.payload),
  };
  if (state == null) {
    return null;
  }

  final isNewTurn = _isNewTurn(event.agentType, eventName);
  final prompt = _extractPromptForEvent(event, eventName);
  final interrupted = state == AgentStatusState.done && _isInterrupted(event)
      ? true
      : event.agentType == AgentType.cursor &&
            eventName == 'afterAgentResponse' &&
            previous?.state == AgentStatusState.done
      ? previous?.interrupted
      : null;
  return NormalizedAgentStatus(
    state: state,
    prompt: prompt.isNotEmpty
        ? prompt
        : (isNewTurn ? '' : previous?.prompt ?? ''),
    toolName: isNewTurn ? null : toolSnapshot.toolName ?? previous?.toolName,
    toolInput: isNewTurn
        ? null
        : toolSnapshot.toolInput ??
              (toolSnapshot.hasToolUpdate ? null : previous?.toolInput),
    lastAssistantMessage:
        toolSnapshot.lastAssistantMessage ?? previous?.lastAssistantMessage,
    interrupted: interrupted,
  );
}

bool isAgentSessionCloseHookEvent(AgentHookEvent event) {
  final eventName = agentHookEventName(event);
  if (eventName == null) {
    return false;
  }
  return switch (event.agentType) {
    AgentType.copilot => eventName == 'SessionEnd',
    AgentType.cursor => eventName == 'sessionEnd',
    AgentType.pi => eventName == 'session_shutdown',
    AgentType.codex ||
    AgentType.claude ||
    AgentType.agy ||
    AgentType.opencode ||
    AgentType.amp => false,
    AgentType.grok => _normalizeGrokEventName(eventName) == 'SessionEnd',
  };
}

bool isAgentSessionResetHookEvent(AgentHookEvent event) {
  final eventName = agentHookEventName(event);
  return event.agentType == AgentType.grok && eventName == 'SessionStart';
}

String? agentHookEventName(AgentHookEvent event) {
  final explicit = _readFirstString(
    <String, Object?>{'hookEventName': event.hookEventName},
    const <String>['hookEventName'],
  );
  final raw =
      explicit ??
      _readFirstString(event.payload, const <String>[
        'hook_event_name',
        'hookEventName',
        'hook_type',
        'hookType',
      ]);
  if (event.agentType == AgentType.copilot) {
    return _normalizeCopilotEventName(
      raw ?? _inferCopilotEventName(event.payload),
    );
  }
  if (event.agentType == AgentType.grok) {
    return _normalizeGrokEventName(raw);
  }
  return raw;
}

bool _isNewTurn(AgentType agentType, String eventName) {
  return switch (agentType) {
    AgentType.codex => _isCodexNewTurn(eventName),
    AgentType.claude => _isClaudeNewTurn(eventName),
    AgentType.copilot => _isCopilotNewTurn(eventName),
    AgentType.cursor => _isCursorNewTurn(eventName),
    AgentType.agy => _isAgyNewTurn(eventName),
    AgentType.opencode => _isOpenCodeNewTurn(eventName),
    AgentType.pi => _isPiNewTurn(eventName),
    AgentType.amp => _isAmpNewTurn(eventName),
    AgentType.grok => _isGrokNewTurn(eventName),
  };
}

String _extractPromptForEvent(AgentHookEvent event, String eventName) {
  if (event.agentType == AgentType.copilot && eventName == 'Notification') {
    return '';
  }
  if (event.agentType == AgentType.grok && eventName == 'Notification') {
    return '';
  }
  if (event.agentType == AgentType.opencode) {
    final prompt = _openCodePromptForEvent(event, eventName);
    if (prompt != null) {
      return prompt;
    }
  }
  final direct = _extractPrompt(event.payload);
  if (direct.isNotEmpty) {
    return event.agentType == AgentType.grok
        ? _stripGrokUserQueryWrapper(direct)
        : direct;
  }
  if (event.agentType == AgentType.agy) {
    return _agyPromptForEvent(event) ?? '';
  }
  return '';
}

String _extractPrompt(Map<String, Object?> payload) {
  return _readFirstString(payload, const <String>[
        'prompt',
        'user_prompt',
        'userPrompt',
        'initial_prompt',
        'initialPrompt',
        'user_message',
        'userMessage',
        'message',
      ]) ??
      '';
}
