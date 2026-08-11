part of 'mobile_codex_state.dart';

String _kindFor(String type, String method) {
  if (type.contains('agentmessage') || type.contains('assistant')) {
    return 'assistantMessage';
  }
  if (type.contains('reason')) return 'reasoning';
  if (type.contains('filechange') ||
      type.contains('diff') ||
      method.contains('filechange')) {
    return 'diff';
  }
  if (type.contains('command') || method.contains('commandexecution')) {
    return 'command';
  }
  if (type.contains('subagent') ||
      type.contains('collab') ||
      method.contains('subagent')) {
    return 'subAgent';
  }
  if (type.contains('plan') || method.contains('/plan')) return 'plan';
  if (type.contains('contextcompaction') ||
      type.contains('enteredreviewmode') ||
      type.contains('exitedreviewmode') ||
      type.contains('tool') ||
      method.contains('tool') ||
      method == 'output') {
    return 'toolCall';
  }
  return 'progressText';
}

String _titleFor(String type, String method, Map<String, Object?> item) {
  if (type.contains('contextcompaction')) {
    return method.contains('completed') ? 'Compacted' : 'Compacting';
  }
  if (type.contains('enteredreviewmode')) return 'Entered review mode';
  if (type.contains('exitedreviewmode')) return 'Exited review mode';
  final explicit = _first(<Object?>[
    item['title'],
    item['name'],
    item['command'],
  ]);
  if (explicit.isNotEmpty) return explicit;
  if (type.contains('command') || method.contains('commandexecution')) {
    return 'Command';
  }
  if (type.contains('filechange') || method.contains('filechange')) {
    return 'File changes';
  }
  if (type.contains('reason')) return 'Reasoning';
  if (type.contains('plan') || method.contains('/plan')) return 'Plan';
  if (type.contains('tool') || method.contains('tool')) return 'Tool call';
  return 'Codex activity';
}

String _rawFirst(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return '';
}
