part of 'terminal_host_client.dart';

Future<TerminalHostAttachment> _createOrAttachTerminal(
  SocketTerminalHostClient client, {
  required String sessionId,
  required String workspaceId,
  required String tabId,
  required String workingDirectory,
  required GhosttyTerminalShellLaunch launch,
  required int cols,
  required int rows,
}) async {
  final payload = await client._terminalRequestMap(
    'createOrAttach',
    _terminalAttachmentRequest(
      sessionId: sessionId,
      workspaceId: workspaceId,
      tabId: tabId,
      workingDirectory: workingDirectory,
      launch: launch,
      cols: cols,
      rows: rows,
    ),
  );
  return TerminalHostAttachment.fromJson(payload);
}

Future<TerminalHostAttachment> _restartTerminal(
  SocketTerminalHostClient client, {
  required String sessionId,
  required String workspaceId,
  required String tabId,
  required String workingDirectory,
  required GhosttyTerminalShellLaunch launch,
  required int cols,
  required int rows,
}) async {
  if (!client.supportsTerminalRestart) {
    throw UnsupportedError(
      'The running terminal host does not support terminal restart.',
    );
  }
  final key = '$workspaceId:$tabId:$sessionId';
  final operationId = client._pendingTerminalRestarts.putIfAbsent(
    key,
    () => const Uuid().v4(),
  );
  final payload = await client._terminalRequestMap(
    'terminal.restart',
    <String, Object?>{
      'operationId': operationId,
      ..._terminalAttachmentRequest(
        sessionId: sessionId,
        workspaceId: workspaceId,
        tabId: tabId,
        workingDirectory: workingDirectory,
        launch: launch,
        cols: cols,
        rows: rows,
      ),
    },
  );
  final attachment = TerminalHostAttachment.fromJson(payload);
  if (client._pendingTerminalRestarts[key] == operationId) {
    client._pendingTerminalRestarts.remove(key);
  }
  return attachment;
}

Map<String, Object?> _terminalAttachmentRequest({
  required String sessionId,
  required String workspaceId,
  required String tabId,
  required String workingDirectory,
  required GhosttyTerminalShellLaunch launch,
  required int cols,
  required int rows,
}) {
  return <String, Object?>{
    'sessionId': sessionId,
    'workspaceId': workspaceId,
    'tabId': tabId,
    'workingDirectory': workingDirectory,
    'launch': TerminalHostLaunch(
      label: launch.label,
      shell: launch.shell,
      arguments: launch.arguments,
      environment: launch.environment ?? const <String, String>{},
    ).toJson(),
    'cols': cols,
    'rows': rows,
  };
}
