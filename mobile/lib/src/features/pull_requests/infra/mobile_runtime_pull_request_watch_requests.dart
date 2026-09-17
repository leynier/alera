import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/pull_requests/domain/mobile_pull_request_watch.dart';

mixin MobileRuntimePullRequestWatchRequests
    implements MobilePullRequestWatchClient {
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
  Future<List<MobilePullRequestWatch>> listPullRequestWatches() async {
    final payload = await requestMap('pullRequestWatch.list');
    return <MobilePullRequestWatch>[
      for (final item in payload.objectList('items'))
        MobilePullRequestWatch.fromJson(asJsonMap(item)),
    ];
  }
}
