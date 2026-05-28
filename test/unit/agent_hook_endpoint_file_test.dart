import 'package:alera/src/features/agent_status/infra/agent_hook_endpoint_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agent hook endpoint files', () {
    test('renders POSIX endpoint env files', () {
      expect(
        buildAgentHookEndpointFileContent(
          kind: AgentHookEndpointFileKind.posix,
          port: 4567,
          token: 'abc-123',
        ),
        'ALERA_AGENT_HOOK_PORT=4567\n'
        'ALERA_AGENT_HOOK_TOKEN=abc-123\n'
        'ALERA_AGENT_HOOK_VERSION=1\n',
      );
    });

    test('renders Windows endpoint cmd files', () {
      expect(
        agentHookEndpointFileName(kind: AgentHookEndpointFileKind.windows),
        'endpoint.cmd',
      );
      expect(
        buildAgentHookEndpointFileContent(
          kind: AgentHookEndpointFileKind.windows,
          port: 4567,
          token: 'abc-123',
        ),
        'set ALERA_AGENT_HOOK_PORT=4567\r\n'
        'set ALERA_AGENT_HOOK_TOKEN=abc-123\r\n'
        'set ALERA_AGENT_HOOK_VERSION=1\r\n',
      );
    });

    test('rejects shell-unsafe values', () {
      expect(
        () => buildAgentHookEndpointFileContent(
          kind: AgentHookEndpointFileKind.posix,
          port: 4567,
          token: 'abc;rm',
        ),
        throwsFormatException,
      );
    });
  });
}
