import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_event_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

part 'grok_agent_hook_event_normalizer_test_cases.dart';
part 'agy_agent_hook_event_normalizer_test_cases.dart';
part 'agent_hook_event_normalizer_test_harness.dart';

void main() {
  group('agent hook event normalizer', () {
    _registerGrokAgentHookEventNormalizerTests();
    _registerAgyAgentHookEventNormalizerTests();

    test('reads assistant messages from Codex transcript formats', () {
      expect(
        _normalizeStopWithTranscript(<String>[
          jsonEncode(<String, Object?>{
            'type': 'assistant.message',
            'data': <String, Object?>{'content': 'Assistant data'},
          }),
          '{not json',
          jsonEncode('plain json string'),
          jsonEncode(<String, Object?>{'role': 'user', 'content': 'skip'}),
        ])?.lastAssistantMessage,
        'Assistant data',
      );

      expect(
        _normalizeStopWithTranscript(<String>[
          jsonEncode(<String, Object?>{
            'source': 'MODEL',
            'type': 'PLANNER_RESPONSE',
            'content': 'Planner response',
          }),
          jsonEncode(<String, Object?>{
            'type': 'assistant.message',
            'data': 'not a map',
          }),
        ])?.lastAssistantMessage,
        'Planner response',
      );

      expect(
        _normalizeStopWithTranscript(<String>[
          jsonEncode(<String, Object?>{
            'message': <String, Object?>{
              'role': 'assistant',
              'content': <Object?>[
                <String, Object?>{'text': ''},
                <String, Object?>{'text': 'List content'},
              ],
            },
          }),
          jsonEncode(<String, Object?>{'role': 'assistant', 'content': ''}),
        ])?.lastAssistantMessage,
        'List content',
      );

      expect(
        _normalizeStopWithTranscript(<String>[
          jsonEncode(<String, Object?>{
            'type': 'assistant',
            'content': 'Direct assistant content',
          }),
        ])?.lastAssistantMessage,
        'Direct assistant content',
      );
    });

    test('reads user prompts from AGY transcripts', () {
      expect(
        _normalizeAgyPromptWithTranscript(<String>[
          jsonEncode(<String, Object?>{
            'source': 'USER_EXPLICIT',
            'type': 'REQUEST',
            'content': '<USER_REQUEST>\n  Build the feature \n</USER_REQUEST>',
          }),
          '{not json',
          jsonEncode(<String, Object?>{'source': 'USER', 'type': 'OTHER'}),
        ])?.prompt,
        'Build the feature',
      );

      expect(
        _normalizeAgyPromptWithTranscript(<String>[
          jsonEncode(<String, Object?>{
            'source': 'USER',
            'type': 'USER_INPUT',
            'content': 'Run the checks',
          }),
          jsonEncode(<String, Object?>{
            'source': 'USER',
            'type': 'USER_INPUT',
            'content': '   ',
          }),
        ])?.prompt,
        'Run the checks',
      );
    });

    test('handles empty, missing, unreadable, and large transcripts', () {
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .codex,
            hookEventName: 'Stop',
            payload: const <String, Object?>{'transcript_path': ''},
          ),
        )?.lastAssistantMessage,
        isNull,
      );

      final empty = _transcript(<String>[]);
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .codex,
            hookEventName: 'Stop',
            payload: <String, Object?>{'transcript_path': empty.path},
          ),
        )?.lastAssistantMessage,
        isNull,
      );

      final missingPath = '${empty.path}-missing';
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .codex,
            hookEventName: 'Stop',
            payload: <String, Object?>{'transcriptPath': missingPath},
          ),
        )?.lastAssistantMessage,
        isNull,
      );

      final large = _largeTranscript(
        jsonEncode(<String, Object?>{
          'message': <String, Object?>{
            'role': 'assistant',
            'content': 'Tail assistant message',
          },
        }),
      );
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .codex,
            hookEventName: 'Stop',
            payload: <String, Object?>{'transcript_path': large.path},
          ),
        )?.lastAssistantMessage,
        'Tail assistant message',
      );
    });

    test('infers Copilot event names and tool snapshots', () {
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .copilot,
            hookEventName: '',
            payload: const <String, Object?>{'initial_prompt': 'Plan the work'},
          ),
        )?.state,
        AgentStatusState.working,
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .copilot,
            hookEventName: '',
            payload: const <String, Object?>{'prompt': 'Ship it'},
          ),
        )?.prompt,
        'Ship it',
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .copilot,
            hookEventName: '',
            payload: const <String, Object?>{
              'notification_type': 'permission_prompt',
              'message': 'Approve command?',
            },
          ),
        )?.state,
        AgentStatusState.blocked,
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .copilot,
            hookEventName: '',
            payload: const <String, Object?>{
              'stop_reason': 'done',
              'lastAssistantMessage': 'Finished',
            },
          ),
        )?.state,
        AgentStatusState.done,
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .copilot,
            hookEventName: '',
            payload: const <String, Object?>{
              'error_context': 'network',
              'recoverable': true,
            },
          ),
        )?.state,
        AgentStatusState.working,
      );

      final postTool = normalizeAgentHookEvent(
        _event(
          agentType: .copilot,
          hookEventName: '',
          payload: const <String, Object?>{
            'toolCalls': <Object?>[
              <String, Object?>{
                'name': 'Bash',
                'arguments': '{"command":"flutter test"}',
              },
            ],
            'toolResult': <String, Object?>{'text': 'ok'},
          },
        ),
      );
      expect(postTool?.state, AgentStatusState.working);
      expect(postTool?.toolName, 'Bash');
      expect(postTool?.toolInput, 'flutter test');
      expect(postTool?.lastAssistantMessage, 'ok');
    });

    test('Claude AskUserQuestion maps to waiting', () {
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .claude,
            hookEventName: 'AskUserQuestion',
            payload: const <String, Object?>{},
          ),
        )?.state,
        AgentStatusState.waiting,
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .claude,
            hookEventName: 'PreToolUse',
            payload: const <String, Object?>{
              'tool_name': 'AskUserQuestion',
              'tool_input': <String, Object?>{'questions': 'Continue?'},
            },
          ),
        )?.state,
        AgentStatusState.waiting,
      );
    });

    test('extracts nested Codex tool calls and input previews', () {
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .codex,
            hookEventName: 'PreToolUse',
            payload: const <String, Object?>{
              'tool_calls': <Object?>[
                <String, Object?>{
                  'tool_name': 'Edit',
                  'args': '{"file_path":"lib/main.dart"}',
                },
              ],
            },
          ),
        )?.toolInput,
        'lib/main.dart',
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .codex,
            hookEventName: 'PreToolUse',
            payload: const <String, Object?>{
              'toolCall': <String, Object?>{
                'toolName': 'Ask',
                'arguments': <String, Object?>{
                  'questions': <Object?>[
                    <String, Object?>{'Question': 'Which target?'},
                  ],
                },
              },
            },
          ),
        )?.toolInput,
        'Which target?',
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .codex,
            hookEventName: 'PreToolUse',
            payload: const <String, Object?>{
              'tool_name': 'List',
              'tool_input': <Object?>['one', 'two'],
            },
          ),
        )?.toolInput,
        'one',
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .codex,
            hookEventName: 'PreToolUse',
            payload: const <String, Object?>{
              'tool_calls': <Object?>[
                <String, Object?>{
                  'name': 'RawArgs',
                  'arguments': 'raw arguments',
                },
              ],
            },
          ),
        )?.toolInput,
        'raw arguments',
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .codex,
            hookEventName: 'PreToolUse',
            payload: const <String, Object?>{
              'tool_name': 'NumberList',
              'tool_input': <Object?>[1, 2],
            },
          ),
        )?.toolInput,
        '1, 2',
      );
    });

    test('covers Copilot permission and response inference variants', () {
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .copilot,
            hookEventName: 'PreToolUse',
            payload: const <String, Object?>{
              'tool_name': 'AskUser',
              'tool_input': <String, Object?>{'question': 'Proceed?'},
            },
          ),
        )?.state,
        AgentStatusState.blocked,
      );

      final response = normalizeAgentHookEvent(
        _event(
          agentType: .copilot,
          hookEventName: '',
          payload: const <String, Object?>{
            'name': 'Shell',
            'tool_response': <String, Object?>{'message': 'completed'},
          },
        ),
      );
      expect(response?.state, AgentStatusState.working);
      expect(response?.lastAssistantMessage, 'completed');

      final camelResponse = normalizeAgentHookEvent(
        _event(
          agentType: .copilot,
          hookEventName: '',
          payload: const <String, Object?>{
            'toolName': 'Shell',
            'toolResponse': <String, Object?>{'message': 'camel completed'},
          },
        ),
      );
      expect(camelResponse?.lastAssistantMessage, 'camel completed');

      final argsFallback = normalizeAgentHookEvent(
        _event(
          agentType: .copilot,
          hookEventName: '',
          payload: const <String, Object?>{
            'toolCalls': <Object?>[
              <String, Object?>{
                'name': 'Shell',
                'args': <String, Object?>{'command': 'dart test'},
              },
            ],
          },
        ),
      );
      expect(argsFallback?.toolInput, 'dart test');

      final rawArgumentsFallback = normalizeAgentHookEvent(
        _event(
          agentType: .copilot,
          hookEventName: '',
          payload: const <String, Object?>{
            'toolCalls': <Object?>[
              <String, Object?>{'name': 'Shell', 'arguments': 'npm test'},
            ],
          },
        ),
      );
      expect(rawArgumentsFallback?.toolInput, 'npm test');
    });

    test('truncates long single-line and multiline previews', () {
      final longPrompt = List<String>.filled(240, 'x').join();
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .copilot,
            hookEventName: 'UserPromptSubmit',
            payload: <String, Object?>{'prompt': longPrompt},
          ),
        )?.prompt.length,
        200,
      );

      final longResponse =
          '${List<String>.filled(2000, 'line').join('\n')}\n\n\ntrailing';
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .amp,
            hookEventName: 'agent.end',
            payload: <String, Object?>{
              'messages': <Object?>[
                <String, Object?>{'role': 'assistant', 'content': longResponse},
              ],
            },
          ),
        )?.lastAssistantMessage?.length,
        8000,
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .codex,
            hookEventName: 'PreToolUse',
            payload: const <String, Object?>{
              'tool_name': 'Custom',
              'tool_input': <String, Object?>{
                'query': <Object?>['alpha', 'beta'],
              },
            },
          ),
        )?.toolInput,
        'alpha, beta',
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .copilot,
            hookEventName: 'Notification',
            payload: const <String, Object?>{
              'notification_type': 'permission_prompt',
              'body': 'Needs review',
            },
          ),
        )?.lastAssistantMessage,
        'Needs review',
      );
    });

    test('ends the Cursor approval wait when the execution starts', () {
      final shell = normalizeAgentHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'afterShellExecution',
          payload: const <String, Object?>{'command': 'sleep 30'},
        ),
      );
      expect(shell?.state, AgentStatusState.working);
      expect(shell?.toolName, 'Shell');
      expect(shell?.toolInput, 'sleep 30');

      final mcp = normalizeAgentHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'afterMCPExecution',
          payload: const <String, Object?>{'tool_name': 'Browser'},
        ),
      );
      expect(mcp?.state, AgentStatusState.working);
      expect(mcp?.toolName, 'Browser');
    });

    test('extracts Cursor shell, MCP, and tool response snapshots', () {
      final shell = normalizeAgentHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'beforeShellExecution',
          payload: const <String, Object?>{'command': 'flutter test'},
        ),
      );
      expect(shell?.state, AgentStatusState.waiting);
      expect(shell?.toolName, 'Shell');
      expect(shell?.toolInput, 'flutter test');

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .cursor,
            hookEventName: 'beforeMCPExecution',
            payload: const <String, Object?>{
              'toolName': 'Browser',
              'url': 'https://example.test',
            },
          ),
        )?.toolInput,
        'https://example.test',
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .cursor,
            hookEventName: 'postToolUse',
            payload: const <String, Object?>{'output': 'tool done'},
          ),
        )?.lastAssistantMessage,
        'tool done',
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .cursor,
            hookEventName: 'postToolUseFailure',
            payload: const <String, Object?>{'error': 'tool failed'},
          ),
        )?.lastAssistantMessage,
        'tool failed',
      );

      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .cursor,
            hookEventName: 'preToolUse',
            payload: const <String, Object?>{
              'toolName': 'JsonFallback',
              'input': 42,
            },
          ),
        )?.toolInput,
        '42',
      );
    });

    test('covers additional agent state transitions', () {
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .agy,
            hookEventName: 'PostInvocation',
            payload: const <String, Object?>{},
          ),
        )?.state,
        AgentStatusState.working,
      );
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .agy,
            hookEventName: 'Unknown',
            payload: const <String, Object?>{},
          ),
        ),
        isNull,
      );

      final previous = AgentStatusEntry(
        terminalSessionId: 'session-1',
        workspaceId: 'workspace-1',
        tabId: 'tab-1',
        agentType: .cursor,
        state: .done,
        prompt: 'old prompt',
        updatedAt: .utc(2026, 5, 26),
        stateStartedAt: .utc(2026, 5, 26),
        interrupted: true,
      );
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .cursor,
            hookEventName: 'afterAgentResponse',
            payload: const <String, Object?>{'message': 'done again'},
          ),
          previous: previous,
        )?.interrupted,
        isTrue,
      );
    });

    test('detects Amp new turn and prompt on agent.start', () {
      final normalized = normalizeAgentHookEvent(
        _event(
          agentType: .amp,
          hookEventName: 'agent.start',
          payload: const <String, Object?>{'message': 'Ship the feature'},
        ),
      );
      expect(normalized?.state, AgentStatusState.working);
      expect(normalized?.prompt, 'Ship the feature');
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .amp,
            hookEventName: 'session.start',
            payload: const <String, Object?>{'threadId': 'thread-1'},
          ),
        ),
        isNull,
      );
    });
  });
}
