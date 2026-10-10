import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/pull_requests/domain/mobile_pull_request_watch.dart';

mixin MobileRuntimePullRequestWatchRequests
    implements
        MobilePullRequestWatchExecutionClient,
        MobilePullRequestAgentDispatchClient {
  Set<String> get runtimeCapabilities;
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  @override
  bool get supportsPullRequestWatch =>
      runtimeCapabilities.contains(pullRequestWatchCapability);

  /// V1 is GitHub execution; V2 adds GitLab and Azure DevOps. Either way the
  /// runtime owns the watch, so the phone never evaluates it as well.
  @override
  bool get supportsPullRequestWatchExecution =>
      runtimeCapabilities.contains('pullRequestWatchExecutionV1') ||
      runtimeCapabilities.contains('pullRequestWatchExecutionV2');

  @override
  Future<String?> pullRequestAgentPrompt({
    required String workspaceId,
    required String kind,
    int? reviewNumber,
  }) async {
    if (!runtimeCapabilities.contains('pullRequestAgentDispatchV1')) {
      return null;
    }
    try {
      final payload = await requestMap(
        'pullRequest.agentDispatch',
        <String, Object?>{
          'workspaceId': workspaceId,
          'kind': kind,
          'number': ?reviewNumber,
        },
      );
      final prompt = payload['prompt'];
      return prompt is String && prompt.trim().isNotEmpty ? prompt : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> startPullRequestWatch(Map<String, Object?> watch) async {
    await requestMap('pullRequestWatch.start', watch);
  }

  @override
  Future<void> stopPullRequestWatch(String workspaceId) async {
    await requestMap('pullRequestWatch.stop', <String, Object?>{
      'workspaceId': workspaceId,
    });
  }

  @override
  Future<List<MobilePullRequestWatch>> listPullRequestWatches() async {
    final payload = await requestMap('pullRequestWatch.list');
    return <MobilePullRequestWatch>[
      for (final item in payload.objectList('items'))
        MobilePullRequestWatch.fromJson(asJsonMap(item)),
    ];
  }
}
