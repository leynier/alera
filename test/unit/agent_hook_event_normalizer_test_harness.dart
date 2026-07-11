part of 'agent_hook_event_normalizer_test.dart';

NormalizedAgentStatus? _normalizeStopWithTranscript(List<String> lines) {
  final file = _transcript(lines);
  return normalizeAgentHookEvent(
    _event(
      agentType: AgentType.codex,
      hookEventName: 'Stop',
      payload: <String, Object?>{'transcript_path': file.path},
    ),
  );
}

NormalizedAgentStatus? _normalizeAgyPromptWithTranscript(List<String> lines) {
  final file = _transcript(lines);
  return normalizeAgentHookEvent(
    _event(
      agentType: AgentType.agy,
      hookEventName: 'PreInvocation',
      payload: <String, Object?>{'transcriptPath': file.path},
    ),
  );
}

AgentHookEvent _event({
  required AgentType agentType,
  required String hookEventName,
  required Map<String, Object?> payload,
}) {
  return AgentHookEvent(
    terminalSessionId: 'session-1',
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: agentType,
    hookEventName: hookEventName,
    payload: payload,
  );
}

File _transcript(List<String> lines) {
  final directory = Directory.systemTemp.createTempSync(
    'alera-transcript-normalizer-',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return File('${directory.path}/transcript.jsonl')
    ..writeAsStringSync(lines.join('\n'));
}

File _largeTranscript(String tailLine) {
  final file = _transcript(<String>[]);
  final filler = List<String>.filled(4 * 1000 * 1000 + 128, 'x').join();
  file.writeAsStringSync('$filler\n$tailLine\n');
  return file;
}
