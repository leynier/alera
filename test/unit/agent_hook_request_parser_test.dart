import 'dart:convert';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_request_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agent hook request parsing', () {
    test('parses JSON bodies with structured payloads', () {
      final decoded = decodeAgentHookRequestBody(
        contentType: 'application/json; charset=utf-8',
        bodyBytes: utf8.encode(
          jsonEncode(<String, Object?>{
            'terminalSessionId': 'session-1',
            'workspaceId': 'workspace-1',
            'tabId': 'tab-1',
            'hookEventName': 'UserPromptSubmit',
            'version': '1',
            'payload': <String, Object?>{'prompt': 'build it'},
          }),
        ),
      );

      final event = parseAgentHookRequest(
        agentType: AgentType.codex,
        body: decoded,
      );

      expect(event, isNotNull);
      expect(event!.terminalSessionId, 'session-1');
      expect(event.workspaceId, 'workspace-1');
      expect(event.tabId, 'tab-1');
      expect(event.agentType, AgentType.codex);
      expect(event.hookEventName, 'UserPromptSubmit');
      expect(event.version, '1');
      expect(event.payload['prompt'], 'build it');
    });

    test('parses form bodies with JSON payload fields', () {
      final form = Uri(
        queryParameters: <String, String>{
          'terminalSessionId': 'session-2',
          'workspaceId': 'workspace-2',
          'tabId': 'tab-2',
          'hook_event_name': 'PreToolUse',
          'payload': jsonEncode(<String, Object?>{
            'tool_name': 'Bash',
            'tool_input': <String, Object?>{'command': 'flutter test'},
          }),
        },
      ).query;
      final decoded = decodeAgentHookRequestBody(
        contentType: 'application/x-www-form-urlencoded',
        bodyBytes: utf8.encode(form),
      );

      final event = parseAgentHookRequest(
        agentType: AgentType.claude,
        body: decoded,
      );

      expect(event, isNotNull);
      expect(event!.agentType, AgentType.claude);
      expect(event.hookEventName, 'PreToolUse');
      expect(event.payload['tool_name'], 'Bash');
    });

    test('returns null for missing metadata and malformed payloads', () {
      expect(
        parseAgentHookRequest(
          agentType: AgentType.codex,
          body: <String, Object?>{
            'workspaceId': 'workspace-1',
            'tabId': 'tab-1',
            'payload': <String, Object?>{},
          },
        ),
        isNull,
      );

      expect(
        parseAgentHookRequest(
          agentType: AgentType.codex,
          body: <String, Object?>{
            'terminalSessionId': 'session-1',
            'workspaceId': 'workspace-1',
            'tabId': 'tab-1',
            'payload': '{not json',
          },
        ),
        isNull,
      );
    });

    test('rejects over-sized bodies', () {
      expect(
        () => decodeAgentHookRequestBody(
          contentType: 'application/json',
          bodyBytes: List<int>.filled(agentHookRequestMaxBytes + 1, 65),
        ),
        throwsFormatException,
      );
    });
  });
}
