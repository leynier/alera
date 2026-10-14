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
  bool observe = false,
  CommandTerminalProviderSetup? providerSetup,
}) async {
  final payload = await client._terminalRequestMap(
    'createOrAttach',
    <String, Object?>{
      ..._terminalAttachmentRequest(
        sessionId: sessionId,
        workspaceId: workspaceId,
        tabId: tabId,
        workingDirectory: workingDirectory,
        launch: launch,
        providerSetup: providerSetup,
        cols: cols,
        rows: rows,
      ),
      if (observe) 'attachmentMode': 'observe',
    },
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
  CommandTerminalProviderSetup? providerSetup,
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
        providerSetup: providerSetup,
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
  CommandTerminalProviderSetup? providerSetup,
}) {
  return <String, Object?>{
    'sessionId': sessionId,
    'workspaceId': workspaceId,
    'tabId': tabId,
    'workingDirectory': workingDirectory,
    'launch': TerminalHostLaunch(
      providerSetup: providerSetup,
      label: launch.label,
      shell: launch.shell,
      arguments: launch.arguments,
      environment: launch.environment ?? const <String, String>{},
    ).toJson(),
    'cols': cols,
    'rows': rows,
  };
}

extension _ProviderSetupHostTransport on SocketTerminalHostClient {
  Future<TerminalHostAttachment> _providerSetupTerminal({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
    required CommandTerminalProviderSetup providerSetup,
    required bool restart,
  }) async {
    final connection = await _connectTerminal();
    if (!connection.runtimeCapabilities.contains('agentChatProviderSetupV1')) {
      throw UnsupportedError(
        'The running host does not support provider setup terminals.',
      );
    }
    if (restart) {
      return _restartTerminal(
        this,
        sessionId: sessionId,
        workspaceId: workspaceId,
        tabId: tabId,
        workingDirectory: workingDirectory,
        launch: launch,
        cols: cols,
        rows: rows,
        providerSetup: providerSetup,
      );
    }
    return _createOrAttachTerminal(
      this,
      sessionId: sessionId,
      workspaceId: workspaceId,
      tabId: tabId,
      workingDirectory: workingDirectory,
      launch: launch,
      cols: cols,
      rows: rows,
      providerSetup: providerSetup,
    );
  }
}

mixin _ProviderSetupHostClientSupport
    implements TerminalHostProviderSetupClient {
  SocketTerminalHostClient get _providerSetupClient;

  @override
  Future<TerminalHostAttachment> providerSetupTerminal({
    required String sessionId,
    required String workspaceId,
    required String tabId,
    required String workingDirectory,
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
    required CommandTerminalProviderSetup providerSetup,
    bool restart = false,
  }) => _providerSetupClient._providerSetupTerminal(
    sessionId: sessionId,
    workspaceId: workspaceId,
    tabId: tabId,
    workingDirectory: workingDirectory,
    launch: launch,
    cols: cols,
    rows: rows,
    providerSetup: providerSetup,
    restart: restart,
  );
}
