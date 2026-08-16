part of 'mobile_runtime_client.dart';

/// The terminal verbs of the gateway protocol: listing a workspace's tabs,
/// minting and attaching sessions, and the input/viewport RPCs.
mixin MobileRuntimeTerminalRequests {
  Future<Object?> request(
    String type, [
    Map<String, Object?> payload,
    Duration? timeout,
  ]);

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload,
    Duration? timeout,
  ]);

  Future<List<Object?>> requestList(
    String type, [
    Map<String, Object?> payload,
  ]);

  Future<List<WorkspaceTabSummary>> listTabs(String workspaceId) async {
    final payload = await requestList('tab.list', <String, Object?>{
      'workspaceId': workspaceId,
    });
    return <WorkspaceTabSummary>[
      for (final item in payload)
        if (asJsonMap(item).isNotEmpty)
          WorkspaceTabSummary.fromJson(asJsonMap(item)),
    ];
  }

  Future<MobileTerminalSession> createTerminal(
    String workspaceId, {
    String? title,
    int cols = defaultTerminalCols,
    int rows = defaultTerminalRows,
    bool autoCloseOnSuccess = false,
  }) async {
    final payload = await requestMap('terminal.create', <String, Object?>{
      'workspaceId': workspaceId,
      'title': title ?? 'Mobile Terminal',
      'cols': cols,
      'rows': rows,
      if (autoCloseOnSuccess) 'autoCloseOnSuccess': true,
    });
    return MobileTerminalSession.fromJson(payload);
  }

  Future<MobileTerminalSession> attachTerminal(
    String tabId, {
    int? cols,
    int? rows,
  }) async {
    // Omitted rather than defaulted: the host reads a stated viewport as a
    // resize of the live PTY, and a placeholder there is a resize to a size
    // nobody is looking at. An older host still falls back to 80x24 for an
    // absent viewport, so it keeps behaving as it does today.
    final payload = await requestMap('terminal.attach', <String, Object?>{
      'tabId': tabId,
      'cols': ?cols,
      'rows': ?rows,
    });
    return MobileTerminalSession.fromJson(payload);
  }

  Future<MobileTerminalSession> restartTerminal(
    String tabId, {
    String? sessionId,
    int cols = defaultTerminalCols,
    int rows = defaultTerminalRows,
  }) async {
    final payload = await requestMap('terminal.restart', <String, Object?>{
      'tabId': tabId,
      'sessionId': ?sessionId,
      'cols': cols,
      'rows': rows,
    });
    return MobileTerminalSession.fromJson(payload);
  }

  Future<void> writeTerminal(
    String sessionId,
    List<int> bytes, {
    bool bracketedPaste = false,
    bool deferredEnter = false,
  }) async {
    // An empty write still means something with a deferred Enter: that is how
    // the host is asked for a bare submit.
    if (bytes.isEmpty && !deferredEnter) {
      return;
    }
    await request('write', <String, Object?>{
      'sessionId': sessionId,
      'dataBase64': base64Encode(bytes),
      // Omitted when false so an older host sees the payload it sees today.
      if (bracketedPaste) 'bracketedPaste': true,
      if (deferredEnter) 'deferredEnter': true,
    });
  }

  Future<void> resizeTerminal(String sessionId, int cols, int rows) async {
    await request('resize', <String, Object?>{
      'sessionId': sessionId,
      'cols': cols,
      'rows': rows,
    });
  }

  Future<void> detachTerminal(String sessionId) async {
    await request('detach', <String, Object?>{'sessionId': sessionId});
  }

  Future<void> terminateSession(String sessionId) async {
    await request('terminate', <String, Object?>{'sessionId': sessionId});
  }
}
