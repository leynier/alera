import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/codex_transcript_status_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Codex transcript watch replacement', () {
    late Directory tempDir;
    late File oldTranscript;
    late File replacementTranscript;
    late _FakeStatusSink sink;
    late CodexTranscriptStatusWatcher watcher;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'alera-codex-replacement-',
      );
      oldTranscript = File('${tempDir.path}/old-rollout.jsonl');
      replacementTranscript = File('${tempDir.path}/new-rollout.jsonl');
      sink = _FakeStatusSink();
      watcher = CodexTranscriptStatusWatcher(sink, const Duration(minutes: 1));
    });

    tearDown(() {
      watcher.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'drops a read that completes after the old watch is replaced',
      () async {
        oldTranscript.writeAsStringSync(_turnStart('turn-1'));
        watcher.observeHookEvent(
          _event(turnId: 'turn-1', transcriptPath: oldTranscript.path),
        );
        await watcher.scanNowForTesting('session-1');

        oldTranscript.writeAsStringSync(
          _turnComplete('turn-1', 'Old completion must be ignored.'),
          mode: .append,
        );
        final staleScan = watcher.scanNowForTesting('session-1');

        replacementTranscript.writeAsStringSync(_turnStart('turn-2'));
        watcher.observeHookEvent(
          _event(turnId: 'turn-2', transcriptPath: replacementTranscript.path),
        );
        await staleScan;

        expect(sink.events, isEmpty);

        replacementTranscript.writeAsStringSync(
          _turnComplete('turn-2', 'Replacement completion.'),
          mode: .append,
        );
        await watcher.scanNowForTesting('session-1');

        expect(sink.events, hasLength(1));
        expect(sink.events.single.hookEventName, 'Stop');
        expect(
          sink.events.single.payload['last_assistant_message'],
          'Replacement completion.',
        );
      },
    );
  });
}

AgentHookEvent _event({
  required String turnId,
  required String transcriptPath,
}) {
  return AgentHookEvent(
    terminalSessionId: 'session-1',
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: .codex,
    hookEventName: 'UserPromptSubmit',
    payload: <String, Object?>{
      'turn_id': turnId,
      'transcript_path': transcriptPath,
    },
  );
}

String _turnStart(String turnId) {
  return '${jsonEncode(<String, Object?>{
    'type': 'event_msg',
    'payload': <String, Object?>{'type': 'task_started', 'turn_id': turnId},
  })}\n';
}

String _turnComplete(String turnId, String message) {
  return '${jsonEncode(<String, Object?>{
    'type': 'event_msg',
    'payload': <String, Object?>{'type': 'task_complete', 'turn_id': turnId, 'last_agent_message': message},
  })}\n';
}

class _FakeStatusSink implements AgentStatusSink {
  final List<AgentHookEvent> events = <AgentHookEvent>[];

  @override
  void applyHookEvent(AgentHookEvent event) {
    events.add(event);
  }
}
