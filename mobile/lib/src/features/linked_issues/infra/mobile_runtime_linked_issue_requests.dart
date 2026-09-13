import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/linked_issues/domain/mobile_linked_issue.dart';

/// The runtime fetches through a forge CLI with a 45 second budget.
const Duration _issueFetchTimeout = Duration(seconds: 60);

mixin MobileRuntimeLinkedIssueRequests implements MobileLinkedIssueClient {
  Set<String> get runtimeCapabilities;
  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  @override
  bool get supportsLinkedIssues =>
      runtimeCapabilities.contains(linkedIssuesCapability);

  @override
  Future<List<MobileLinkedIssue>> listLinkedIssues() async {
    final payload = await requestMap('linkedIssue.list');
    return <MobileLinkedIssue>[
      for (final item in payload.objectList('items'))
        MobileLinkedIssue.fromJson(asJsonMap(item)),
    ];
  }

  @override
  Future<MobileLinkIssueResult> linkIssue(
    String workspaceId,
    String url,
  ) async {
    return MobileLinkIssueResult.fromJson(
      await requestMap('linkedIssue.link', <String, Object?>{
        'workspaceId': workspaceId,
        'url': url,
      }, _issueFetchTimeout),
    );
  }

  @override
  Future<void> unlinkIssue(String workspaceId) async {
    await request('linkedIssue.remove', <String, Object?>{
      'workspaceId': workspaceId,
    });
  }

  @override
  Future<MobileIssueDetails> fetchIssue(String url) async {
    return MobileIssueDetails.fromJson(
      await requestMap('issue.fetch', <String, Object?>{
        'url': url,
      }, _issueFetchTimeout),
    );
  }
}
