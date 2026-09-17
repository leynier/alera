part of 'mobile_runtime_client.dart';

/// A merge or a create waits on GitHub, not only on the runtime.
const Duration _pullRequestWriteTimeout = Duration(seconds: 90);

/// An agent CLI reading the whole range can take minutes on a large branch.
const Duration _pullRequestDetailsTimeout = Duration(minutes: 5);

/// One summaries request fans out to every repository on the runtime, so it
/// waits on the slowest `gh` batch rather than a single pull request.
const Duration _pullRequestSummariesTimeout = Duration(minutes: 2);

mixin MobileRuntimePullRequestRequests
    implements
        MobilePullRequestActionsClient,
        MobileWorkspacePullRequestSummariesClient {
  Set<String> get runtimeCapabilities;

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  @override
  bool get supportsPullRequestActions =>
      runtimeCapabilities.contains(mobilePullRequestActionsCapability);

  @override
  bool get supportsPullRequestDetailsGeneration =>
      runtimeCapabilities.contains(aiTextPullRequestDetailsCapability);

  @override
  bool get supportsPullRequestShip =>
      runtimeCapabilities.contains(mobilePullRequestShipCapability);

  @override
  bool get supportsPullRequestSummaries =>
      runtimeCapabilities.contains(mobilePullRequestSummariesCapability);

  @override
  Future<Map<String, MobileWorkspacePullRequestSummary>>
  pullRequestSummaries() async {
    if (!supportsPullRequestSummaries) {
      throw UnsupportedError(
        'Update the paired Alera runtime to show pull request status.',
      );
    }
    final payload = await requestMap(
      'mobile.pullRequest.summaries',
      const <String, Object?>{},
      _pullRequestSummariesTimeout,
    );
    final summaries = <String, MobileWorkspacePullRequestSummary>{};
    for (final item in payload.objectList('summaries')) {
      final json = asJsonMap(item);
      if (json.isEmpty) {
        continue;
      }
      final summary = MobileWorkspacePullRequestSummary.fromJson(json);
      summaries[summary.workspaceId] = summary;
    }
    return summaries;
  }

  @override
  Future<MobilePullRequestSnapshot> shipPullRequest({
    required String workspaceId,
    required MobilePullRequestShipInput input,
  }) async {
    if (!supportsPullRequestShip) {
      throw UnsupportedError(
        'Update the paired Alera runtime to ship changes.',
      );
    }
    return MobilePullRequestSnapshot.fromJson(
      await requestMap('mobile.pullRequest.ship', <String, Object?>{
        'workspaceId': workspaceId,
        'baseBranch': input.baseBranch,
        'draft': input.draft,
        'scope': input.stagedOnly ? 'staged' : 'all',
      }, _pullRequestDetailsTimeout),
    );
  }

  @override
  Future<MobilePullRequestDetails> generatePullRequestDetails({
    required String workspaceId,
    required String baseBranch,
  }) async {
    if (!supportsPullRequestDetailsGeneration) {
      throw UnsupportedError(
        'Update the paired Alera runtime to generate pull request details.',
      );
    }
    final payload = await requestMap('aiText.pullRequestDetails.generate', <
      String,
      Object?
    >{
      'operationId':
          'mobile-pull-request-details-${DateTime.now().microsecondsSinceEpoch}',
      'workspaceId': workspaceId,
      'baseBranch': baseBranch,
    }, _pullRequestDetailsTimeout);
    return (
      title: payload.optionalString('title') ?? '',
      body: payload.optionalString('body') ?? '',
    );
  }

  Future<MobilePullRequestSnapshot> _pullRequestWrite(
    String verb,
    Map<String, Object?> payload,
  ) async {
    if (!supportsPullRequestActions) {
      throw UnsupportedError(
        'Update the paired Alera runtime to change pull requests.',
      );
    }
    return MobilePullRequestSnapshot.fromJson(
      await requestMap(
        'mobile.pullRequest.$verb',
        payload,
        _pullRequestWriteTimeout,
      ),
    );
  }

  @override
  Future<MobilePullRequestSnapshot> commentOnPullRequest({
    required String workspaceId,
    required int number,
    required String body,
    int? replyToCommentId,
  }) {
    return _pullRequestWrite('comment', <String, Object?>{
      'workspaceId': workspaceId,
      'number': number,
      'body': body,
      'replyToCommentId': ?replyToCommentId,
    });
  }

  @override
  Future<MobilePullRequestSnapshot> editPullRequestComment({
    required String workspaceId,
    required int number,
    required MobilePullRequestComment comment,
    required String body,
  }) {
    return _pullRequestWrite('commentUpdate', <String, Object?>{
      'workspaceId': workspaceId,
      'number': number,
      'commentId': comment.id,
      'source': comment.source,
      'body': body,
    });
  }

  @override
  Future<MobilePullRequestSnapshot> mergePullRequest({
    required String workspaceId,
    required int number,
    required MobilePullRequestMergeMethod method,
  }) {
    return _pullRequestWrite('merge', <String, Object?>{
      'workspaceId': workspaceId,
      'number': number,
      'method': method.wireName,
    });
  }

  @override
  Future<MobilePullRequestSnapshot> setPullRequestDraft({
    required String workspaceId,
    required int number,
    required bool draft,
  }) {
    return _pullRequestWrite('draftStatus', <String, Object?>{
      'workspaceId': workspaceId,
      'number': number,
      'draft': draft,
    });
  }

  @override
  Future<MobilePullRequestSnapshot> closePullRequest({
    required String workspaceId,
    required int number,
  }) {
    return _pullRequestWrite('close', <String, Object?>{
      'workspaceId': workspaceId,
      'number': number,
    });
  }

  @override
  Future<MobilePullRequestSnapshot> linkPullRequest({
    required String workspaceId,
    required String reference,
  }) {
    return _pullRequestWrite('link', <String, Object?>{
      'workspaceId': workspaceId,
      'reference': reference,
    });
  }

  @override
  Future<MobilePullRequestSnapshot> unlinkPullRequest({
    required String workspaceId,
    required int number,
    String? url,
  }) {
    return _pullRequestWrite('unlink', <String, Object?>{
      'workspaceId': workspaceId,
      'number': number,
      'url': ?url,
    });
  }

  @override
  Future<MobilePullRequestSnapshot> createPullRequest({
    required String workspaceId,
    required MobilePullRequestCreateInput input,
  }) {
    return _pullRequestWrite('create', <String, Object?>{
      'workspaceId': workspaceId,
      'baseBranch': input.baseBranch,
      'title': input.title,
      'body': input.body,
      'draft': input.draft,
    });
  }
}
