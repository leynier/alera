import 'package:alera_mobile/src/features/linked_issues/domain/mobile_linked_issue.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'linked_issues_controller.g.dart';

/// Every linked issue on one host, refreshed on `linkedIssuesChanged`.
@riverpod
class LinkedIssuesController extends _$LinkedIssuesController {
  @override
  Future<MobileLinkedIssueSnapshot> build(String hostId) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    if (client is! MobileLinkedIssueClient ||
        !(client as MobileLinkedIssueClient).supportsLinkedIssues) {
      return const MobileLinkedIssueSnapshot();
    }
    final issues = client as MobileLinkedIssueClient;
    final subscription = client.events.listen((event) {
      if (ref.mounted && event.name == 'linkedIssuesChanged') {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(subscription.cancel);
    final links = await issues.listLinkedIssues();
    return MobileLinkedIssueSnapshot(
      supported: true,
      byWorkspace: <String, MobileLinkedIssue>{
        for (final link in links) link.workspaceId: link,
      },
    );
  }

  Future<MobileLinkedIssueClient> _client() async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    return client as MobileLinkedIssueClient;
  }

  Future<MobileLinkIssueResult> link(String workspaceId, String url) async {
    final result = await (await _client()).linkIssue(workspaceId, url);
    if (ref.mounted) {
      ref.invalidateSelf();
    }
    return result;
  }

  Future<void> unlink(String workspaceId) async {
    await (await _client()).unlinkIssue(workspaceId);
    if (ref.mounted) {
      ref.invalidateSelf();
    }
  }

  Future<MobileIssueDetails> fetch(String url) async =>
      (await _client()).fetchIssue(url);
}
