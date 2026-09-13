import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';

/// Pull request writes for [FakeTerminalClient]. Each write records a readable
/// call, then throws [actionError] when set or answers with [nextSnapshot]
/// (falling back to the current [pullRequest]).
mixin FakePullRequestActionsClient implements MobilePullRequestActionsClient {
  List<String> get calls;
  MobilePullRequestSnapshot get pullRequest;
  set pullRequest(MobilePullRequestSnapshot value);

  bool pullRequestActionsSupported = false;
  MobilePullRequestSnapshot? nextSnapshot;
  Object? actionError;

  @override
  bool get supportsPullRequestActions => pullRequestActionsSupported;

  bool pullRequestDetailsSupported = false;
  MobilePullRequestDetails generatedDetails = (title: '', body: '');

  @override
  bool get supportsPullRequestDetailsGeneration => pullRequestDetailsSupported;

  @override
  Future<MobilePullRequestDetails> generatePullRequestDetails({
    required String workspaceId,
    required String baseBranch,
  }) async {
    calls.add('generatePullRequestDetails $baseBranch');
    final error = actionError;
    if (error != null) {
      throw error;
    }
    return generatedDetails;
  }

  Future<MobilePullRequestSnapshot> _answer(String call) async {
    calls.add(call);
    final error = actionError;
    if (error != null) {
      throw error;
    }
    final next = nextSnapshot;
    if (next != null) {
      pullRequest = next;
    }
    return pullRequest;
  }

  @override
  Future<MobilePullRequestSnapshot> commentOnPullRequest({
    required String workspaceId,
    required int number,
    required String body,
    int? replyToCommentId,
  }) => _answer(
    'commentOnPullRequest $number $body'
    '${replyToCommentId == null ? '' : ' reply:$replyToCommentId'}',
  );

  @override
  Future<MobilePullRequestSnapshot> editPullRequestComment({
    required String workspaceId,
    required int number,
    required MobilePullRequestComment comment,
    required String body,
  }) => _answer('editPullRequestComment $number ${comment.id} $body');

  @override
  Future<MobilePullRequestSnapshot> mergePullRequest({
    required String workspaceId,
    required int number,
    required MobilePullRequestMergeMethod method,
  }) => _answer('mergePullRequest $number ${method.wireName}');

  @override
  Future<MobilePullRequestSnapshot> setPullRequestDraft({
    required String workspaceId,
    required int number,
    required bool draft,
  }) => _answer('setPullRequestDraft $number $draft');

  @override
  Future<MobilePullRequestSnapshot> closePullRequest({
    required String workspaceId,
    required int number,
  }) => _answer('closePullRequest $number');

  @override
  Future<MobilePullRequestSnapshot> linkPullRequest({
    required String workspaceId,
    required String reference,
  }) => _answer('linkPullRequest $reference');

  @override
  Future<MobilePullRequestSnapshot> unlinkPullRequest({
    required String workspaceId,
    required int number,
    String? url,
  }) => _answer('unlinkPullRequest $number');

  @override
  Future<MobilePullRequestSnapshot> createPullRequest({
    required String workspaceId,
    required MobilePullRequestCreateInput input,
  }) => _answer(
    'createPullRequest ${input.baseBranch} ${input.title} draft:${input.draft}',
  );
}
