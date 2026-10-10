import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the pull request requests send instead of reaching a runtime.
final class _RecordingRequests with MobileRuntimePullRequestRequests {
  final List<(String, Map<String, Object?>)> requests =
      <(String, Map<String, Object?>)>[];

  @override
  Set<String> get runtimeCapabilities => const <String>{
    mobilePullRequestActionsCapability,
  };

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add((type, payload));
    return <String, Object?>{
      'branch': 'feat/gitlab',
      'provider': 'gitlab',
      'authStatus': 'authenticated',
      'mergeMethods': <String>['providerDefault', 'squash'],
    };
  }
}

void main() {
  test(
    'a provider-default merge sends the wire name the runtime parses',
    () async {
      final requests = _RecordingRequests();

      await requests.mergePullRequest(
        workspaceId: 'workspace-1',
        number: 12,
        method: MobilePullRequestMergeMethod.providerDefault,
      );

      final (type, payload) = requests.requests.single;
      expect(type, 'mobile.pullRequest.merge');
      expect(payload, <String, Object?>{
        'workspaceId': 'workspace-1',
        'number': 12,
        'method': 'providerDefault',
      });
    },
  );

  test('replies and edits name their thread, as Azure DevOps needs', () async {
    final requests = _RecordingRequests();

    await requests.commentOnPullRequest(
      workspaceId: 'workspace-1',
      number: 12,
      body: 'Done',
      replyToCommentId: 1,
      replyToThreadId: '7',
    );
    await requests.editPullRequestComment(
      workspaceId: 'workspace-1',
      number: 12,
      comment: const MobilePullRequestComment(
        id: 1,
        source: 'reviewThread',
        threadId: '8',
      ),
      body: 'Edited',
    );

    expect(requests.requests[0].$2['replyToThreadId'], '7');
    expect(requests.requests[0].$2['replyToCommentId'], 1);
    expect(requests.requests[1].$2['threadId'], '8');
  });
}
