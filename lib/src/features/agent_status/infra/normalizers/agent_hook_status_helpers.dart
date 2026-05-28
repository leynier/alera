part of '../agent_hook_event_normalizer.dart';

bool _isInterrupted(AgentHookEvent event) {
  return switch (event.agentType) {
    AgentType.amp => _isAmpInterrupted(event),
    AgentType.cursor => _isCursorInterrupted(event),
    AgentType.codex ||
    AgentType.claude ||
    AgentType.copilot ||
    AgentType.agy ||
    AgentType.opencode ||
    AgentType.pi => _isGenericInterrupted(event),
  };
}

bool _isGenericInterrupted(AgentHookEvent event) {
  final value = event.payload['is_interrupt'] ?? event.payload['interrupted'];
  return value == true;
}

bool _isHumanInputTool(String? toolName) {
  if (toolName == null) {
    return false;
  }
  final normalized = toolName
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .toLowerCase();
  return _isHumanInputToolName(normalized) ||
      normalized.endsWith('requestuserinput') ||
      normalized.endsWith('askquestion') ||
      normalized.endsWith('askpermission') ||
      normalized.endsWith('askapproval') ||
      normalized.endsWith('requestpermission') ||
      normalized.endsWith('requestpermissions') ||
      normalized.endsWith('requestapproval') ||
      normalized.endsWith('askuser');
}

bool _isHumanInputToolName(String normalizedToolName) {
  return normalizedToolName == 'askquestion' ||
      normalizedToolName == 'askpermission' ||
      normalizedToolName == 'askapproval' ||
      normalizedToolName == 'askuser' ||
      normalizedToolName == 'requestuserinput' ||
      normalizedToolName == 'requestinput' ||
      normalizedToolName == 'requestpermission' ||
      normalizedToolName == 'requestpermissions' ||
      normalizedToolName == 'requestapproval' ||
      normalizedToolName == 'approve' ||
      normalizedToolName == 'approval' ||
      normalizedToolName == 'permission' ||
      normalizedToolName == 'confirm' ||
      normalizedToolName == 'confirmation' ||
      normalizedToolName == 'requestconfirmation';
}

String? _readFirstString(Map<String, Object?> payload, List<String> keys) {
  for (final key in keys) {
    final value = payload[key];
    if (value is String) {
      final normalized = _normalizeSingleLine(value, 200);
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
  }
  return null;
}

String _normalizeSingleLine(String value, int maxLength) {
  final normalized = value.trim().replaceAll(
    RegExp(r'[\r\n\u2028\u2029]+'),
    ' ',
  );
  return normalized.length <= maxLength
      ? normalized
      : normalized.substring(0, maxLength);
}

String _normalizeMultiline(String value, int maxLength) {
  final normalized = value
      .trim()
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[\u2028\u2029]'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return normalized.length <= maxLength
      ? normalized
      : normalized.substring(0, maxLength);
}

const Map<String, List<String>> _toolInputKeysByTool = <String, List<String>>{
  'Bash': <String>['command'],
  'Execute': <String>['command'],
  'Read': <String>['file_path', 'filePath', 'path'],
  'Write': <String>['file_path', 'filePath', 'path'],
  'Edit': <String>['file_path', 'filePath', 'path'],
  'MultiEdit': <String>['file_path', 'filePath', 'path'],
  'Grep': <String>['pattern'],
  'Glob': <String>['pattern'],
  'WebFetch': <String>['url'],
  'WebSearch': <String>['query'],
  'run_command': <String>['CommandLine', 'command'],
  'ask_question': <String>['Prompt', 'question'],
  'ask_permission': <String>['Action', 'Target', 'Reason'],
  'request_user_input': <String>['questions', 'question'],
  'functions.request_user_input': <String>['questions', 'question'],
  'request_permissions': <String>['reason', 'permissions'],
  'functions.request_permissions': <String>['reason', 'permissions'],
  'bash': <String>['command'],
  'read': <String>['file_path', 'filePath', 'path'],
  'write': <String>['file_path', 'filePath', 'path'],
  'edit': <String>['file_path', 'filePath', 'path'],
};

const int _transcriptMaxScanBytes = 4 * 1000 * 1000;

class _NestedToolCall {
  const _NestedToolCall({this.toolName, this.toolInputSource});

  final String? toolName;
  final Object? toolInputSource;
}

class _ToolSnapshot {
  const _ToolSnapshot({
    this.toolName,
    this.toolInput,
    this.lastAssistantMessage,
    this.hasToolUpdate = false,
    this.hasToolInput = false,
  });

  final String? toolName;
  final String? toolInput;
  final String? lastAssistantMessage;
  final bool hasToolUpdate;
  final bool hasToolInput;
}
