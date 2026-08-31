part of 'mobile_runtime_client.dart';

// Covers app-server initialization, the 90-second scan, native fork/boundary
// requests, and response overhead. Keep ordinary runtime requests short.
const _codexHistoryOperationTimeout = Duration(minutes: 7);

/// Codex requests are kept in a part file so the runtime client remains
/// organized by protocol surface. The enclosing client implements
/// [MobileCodexClient].
mixin MobileRuntimeCodexRequests {
  bool get supportsCodexChat;
  bool get supportsCodexGoals;

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);
  Future<WorkspaceTabSummary> createCodexTab(String workspaceId) async {
    final payload = await codexRequest('codex.tab.create', <String, Object?>{
      'workspaceId': workspaceId,
    });
    return WorkspaceTabSummary.fromJson(payload);
  }

  Future<Map<String, Object?>> codexRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    if (!supportsCodexChat) {
      throw UnsupportedError(
        'This runtime host does not support Codex chat tabs.',
      );
    }
    final timeout = switch (type) {
      'codex.thread.fork' ||
      'codex.thread.edit' ||
      'codex.queue.reconcile' => _codexHistoryOperationTimeout,
      _ => null,
    };
    return requestMap(type, payload, timeout);
  }

  Future<Map<String, Object?>> codexGoalRequest(
    String type,
    Map<String, Object?> payload,
  ) {
    if (!supportsCodexGoals) {
      throw UnsupportedError('This runtime host does not support Codex goals.');
    }
    return codexRequest(type, payload);
  }
}
