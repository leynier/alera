part of 'mobile_runtime_client.dart';

/// Codex requests are kept in a part file so the runtime client remains
/// organized by protocol surface. The enclosing client implements
/// [MobileCodexClient].
mixin MobileRuntimeCodexRequests {
  bool get supportsCodexChat;

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
    return requestMap(type, payload);
  }
}
