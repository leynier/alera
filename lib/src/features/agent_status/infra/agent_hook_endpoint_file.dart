import 'dart:io';

import 'package:alera/src/shared/infra/files/posix_file_mode.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

const String aleraAgentHookProtocolVersion = '1';
const String aleraAgentHookTokenHeader = 'X-Alera-Agent-Hook-Token';

enum AgentHookEndpointFileKind { posix, windows }

class const AgentHookEndpoint({
  required final String filePath,
  required final int port,
  required final String token,
  required final String version,
}) {
  Map<String, String> launchEnvironment({
    required String terminalSessionId,
    required String workspaceId,
    required String tabId,
  }) {
    return <String, String>{
      'ALERA_AGENT_HOOK_ENDPOINT': filePath,
      'ALERA_AGENT_HOOK_PORT': port.toString(),
      'ALERA_AGENT_HOOK_TOKEN': token,
      'ALERA_AGENT_HOOK_VERSION': version,
      'ALERA_TERMINAL_SESSION_ID': terminalSessionId,
      'ALERA_WORKSPACE_ID': workspaceId,
      'ALERA_TAB_ID': tabId,
    };
  }
}

String agentHookEndpointFileName({required AgentHookEndpointFileKind kind}) {
  return switch (kind) {
    AgentHookEndpointFileKind.posix => 'endpoint.env',
    AgentHookEndpointFileKind.windows => 'endpoint.cmd',
  };
}

AgentHookEndpointFileKind currentAgentHookEndpointFileKind() {
  return Platform.isWindows
      ? AgentHookEndpointFileKind.windows
      : AgentHookEndpointFileKind.posix;
}

String createAgentHookToken({Uuid uuid = const Uuid()}) => uuid.v4();

String buildAgentHookEndpointFileContent({
  required AgentHookEndpointFileKind kind,
  required int port,
  required String token,
  String version = aleraAgentHookProtocolVersion,
}) {
  final prefix = kind == AgentHookEndpointFileKind.windows ? 'set ' : '';
  final separator = kind == AgentHookEndpointFileKind.windows ? '\r\n' : '\n';
  final values = <String, String>{
    'ALERA_AGENT_HOOK_PORT': port.toString(),
    'ALERA_AGENT_HOOK_TOKEN': token,
    'ALERA_AGENT_HOOK_VERSION': version,
  };
  for (final entry in values.entries) {
    if (!_isShellSafeEndpointValue(entry.value)) {
      throw FormatException(
        'Endpoint value for ${entry.key} is unsafe for shell sourcing.',
      );
    }
  }
  return <String>[
    for (final entry in values.entries) '$prefix${entry.key}=${entry.value}',
    '',
  ].join(separator);
}

Future<void> writeAgentHookEndpointFile({
  required Directory directory,
  required String filePath,
  required AgentHookEndpointFileKind kind,
  required int port,
  required String token,
  String version = aleraAgentHookProtocolVersion,
}) async {
  await directory.create(recursive: true);
  final tmpPath = p.join(
    directory.path,
    '.endpoint-${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  final tmp = File(tmpPath);
  await tmp.writeAsString(
    buildAgentHookEndpointFileContent(
      kind: kind,
      port: port,
      token: token,
      version: version,
    ),
    mode: .writeOnly,
  );
  if (!Platform.isWindows) {
    setPosixFileMode(tmpPath, posixPrivateFileMode);
  }
  await tmp.rename(filePath);
}

bool _isShellSafeEndpointValue(String value) {
  return RegExp(r'^[A-Za-z0-9._:/-]+$').hasMatch(value);
}
