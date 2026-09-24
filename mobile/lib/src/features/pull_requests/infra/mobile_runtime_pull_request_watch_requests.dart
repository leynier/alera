import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/pull_requests/domain/mobile_pull_request_watch.dart';

mixin MobileRuntimePullRequestWatchRequests
    implements MobilePullRequestWatchExecutionClient {
  Set<String> get runtimeCapabilities;
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  @override
  bool get supportsPullRequestWatch =>
      runtimeCapabilities.contains(pullRequestWatchCapability);

  @override
  bool get supportsPullRequestWatchExecution =>
      runtimeCapabilities.contains('pullRequestWatchExecutionV1');

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
