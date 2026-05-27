import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/codex_transcript_status_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CodexTranscriptStatusWatcher', () {
    late Directory tempDir;
    late File transcript;
    late _FakeStatusSink sink;
    late CodexTranscriptStatusWatcher watcher;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'alera-codex-transcript-',
      );
      transcript = File('${tempDir.path}/rollout.jsonl');
      sink = _FakeStatusSink();
      watcher = CodexTranscriptStatusWatcher(sink, const Duration(minutes: 1));
    });

    tearDown(() {
      watcher.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('emits waiting event for request_user_input function call', () async {
      transcript.writeAsStringSync(
        '${jsonEncode(<String, Object?>{
          'type': 'event_msg',
          'payload': <String, Object?>{'type': 'task_started', 'turn_id': 'turn-1'},
        })}\n',
      );
      watcher.observeHookEvent(
        _event(
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{
            'turn_id': 'turn-1',
            'transcript_path': transcript.path,
            'prompt': 'ask me',
          },
        ),
      );
      await watcher.scanNowForTesting('session-1');

      transcript.writeAsStringSync(
        '${jsonEncode(<String, Object?>{
          'type': 'response_item',
          'payload': <String, Object?>{
            'type': 'function_call',
            'name': 'request_user_input',
            'call_id': 'call-1',
            'arguments': jsonEncode(<String, Object?>{
              'questions': <Object?>[
                <String, Object?>{'question': 'Which option?'},
              ],
            }),
          },
        })}\n',
        mode: FileMode.append,
      );
      await watcher.scanNowForTesting('session-1');

      expect(sink.events, hasLength(1));
      final event = sink.events.single;
      expect(event.agentType, AgentType.codex);
      expect(event.hookEventName, 'PreToolUse');
      expect(event.version, 'codex-transcript');
      expect(event.payload['tool_name'], 'request_user_input');
      expect(event.payload['tool_use_id'], 'call-1');
      expect(event.payload['tool_input'], <String, Object?>{
        'questions': <Object?>[
          <String, Object?>{'question': 'Which option?'},
        ],
      });
    });

    test('marks request tool as working again after output', () async {
      transcript.writeAsStringSync('');
      watcher.observeHookEvent(
        _event(
          hookEventName: 'UserPromptSubmit',
          payload: <String, Object?>{
            'turn_id': 'turn-1',
            'transcript_path': transcript.path,
            'prompt': 'ask permission',
          },
        ),
      );
      await watcher.scanNowForTesting('session-1');

      transcript.writeAsStringSync(
        '${jsonEncode(<String, Object?>{
          'type': 'response_item',
          'payload': <String, Object?>{
            'type': 'function_call',
            'name': 'request_permissions',
            'call_id': 'call-1',
            'arguments': jsonEncode(<String, Object?>{'reason': 'Need write access.'}),
          },
        })}\n'
        '${jsonEncode(<String, Object?>{
          'type': 'response_item',
          'payload': <String, Object?>{'type': 'function_call_output', 'call_id': 'call-1', 'output': '{}'},
        })}\n',
        mode: FileMode.append,
      );
      await watcher.scanNowForTesting('session-1');

      expect(sink.events.map((event) => event.hookEventName), <String>[
        'PreToolUse',
        'PostToolUse',
      ]);
      expect(sink.events.first.payload['tool_name'], 'request_permissions');
      expect(sink.events.last.payload['tool_name'], 'request_permissions');
    });

    test(
      'marks interrupted turn as stopped after permission cancellation',
      () async {
        transcript.writeAsStringSync('');
        watcher.observeHookEvent(
          _event(
            hookEventName: 'UserPromptSubmit',
            payload: <String, Object?>{
              'turn_id': 'turn-1',
              'transcript_path': transcript.path,
              'prompt': 'write a file',
            },
          ),
        );
        await watcher.scanNowForTesting('session-1');

        transcript.writeAsStringSync(
          '${jsonEncode(<String, Object?>{
            'type': 'event_msg',
            'payload': <String, Object?>{'type': 'turn_aborted', 'turn_id': 'turn-1', 'reason': 'interrupted'},
          })}\n',
          mode: FileMode.append,
        );
        await watcher.scanNowForTesting('session-1');

        expect(sink.events, hasLength(1));
        final event = sink.events.single;
        expect(event.hookEventName, 'Stop');
        expect(event.version, 'codex-transcript');
        expect(event.payload['is_interrupt'], isTrue);
      },
    );

    test(
      'marks completed transcript turn as stopped with last message',
      () async {
        transcript.writeAsStringSync('');
        watcher.observeHookEvent(
          _event(
            hookEventName: 'UserPromptSubmit',
            payload: <String, Object?>{
              'turn_id': 'turn-1',
              'transcript_path': transcript.path,
              'prompt': 'finish',
            },
          ),
        );
        await watcher.scanNowForTesting('session-1');

        transcript.writeAsStringSync(
          '${jsonEncode(<String, Object?>{
            'type': 'event_msg',
            'payload': <String, Object?>{'type': 'task_complete', 'turn_id': 'turn-1', 'last_agent_message': 'Done.'},
          })}\n',
          mode: FileMode.append,
        );
        await watcher.scanNowForTesting('session-1');

        expect(sink.events, hasLength(1));
        final event = sink.events.single;
        expect(event.hookEventName, 'Stop');
        expect(event.payload['is_interrupt'], isFalse);
        expect(event.payload['last_assistant_message'], 'Done.');
      },
    );
  });
}

AgentHookEvent _event({
  required String hookEventName,
  required Map<String, Object?> payload,
}) {
  return AgentHookEvent(
    terminalSessionId: 'session-1',
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: AgentType.codex,
    hookEventName: hookEventName,
    payload: payload,
  );
}

class _FakeStatusSink implements AgentStatusSink {
  final List<AgentHookEvent> events = <AgentHookEvent>[];

  @override
  void applyHookEvent(AgentHookEvent event) {
    events.add(event);
  }
}
