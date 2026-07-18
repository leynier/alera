import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';

/// Configurable in-memory [ForgeProvider] shared by the pull-request
/// controller suites.
class FakeForgeProvider implements ForgeProvider {
  ForgeAuthStatus auth = ForgeAuthStatus.authenticated;
  HostedReview? branchReview;
  Future<HostedReview?> Function()? branchReviewLoader;
  int branchReviewCalls = 0;
  String? lastBranchQuery;
  final Map<int, HostedReview> byNumber = <int, HostedReview>{};
  List<ReviewCheck> checks = <ReviewCheck>[];
  Future<List<ReviewCheck>> Function()? checksLoader;
  int checksCalls = 0;
  CreateReviewResult createResult = const CreateReviewFailure(
    code: CreateReviewErrorCode.unknown,
    message: 'not set',
  );
  int createCalls = 0;
  Object? createError;
  ReviewCheckDetails? details;
  ReviewCheck? lastDetailsCheck;
  int lastDetailsNumber = -1;
  UpdateReviewResult updateResult = const UpdateReviewFailure(
    code: UpdateReviewErrorCode.unknown,
    message: 'not set',
  );
  UpdateReviewInput? lastUpdateInput;
  int updateCalls = 0;
  List<ReviewMergeMethod> mergeMethods = const <ReviewMergeMethod>[
    ReviewMergeMethod.mergeCommit,
    ReviewMergeMethod.squash,
    ReviewMergeMethod.rebase,
  ];
  bool canCloseReview = true;
  bool canChangeDraftStatus = true;
  bool canComment = true;
  List<ReviewComment> comments = <ReviewComment>[];
  Future<List<ReviewComment>> Function()? commentsLoader;
  int commentsCalls = 0;
  String? lastCommentBody;
  int addCommentCalls = 0;
  Object? addCommentError;
  ReviewMergeMethod? lastMergeMethod;
  int mergeCalls = 0;
  Object? mergeError;
  int closeCalls = 0;
  Object? closeError;
  bool? lastDraftStatus;
  int draftStatusCalls = 0;
  Object? draftStatusError;

  @override
  GitHostingProvider get id => GitHostingProvider.github;

  @override
  bool get supportsReviewCreation => true;

  @override
  List<ReviewMergeMethod> get supportedMergeMethods => mergeMethods;

  @override
  bool get supportsReviewClosure => canCloseReview;

  @override
  bool get supportsReviewDraftConversion => canChangeDraftStatus;

  @override
  bool get supportsReviewComments => canComment;

  @override
  Future<ForgeAuthStatus> checkAuth({
    required GitRemoteIdentity identity,
  }) async => auth;

  @override
  Future<HostedReview?> getReviewForBranch({
    required GitRemoteIdentity identity,
    required String repoPath,
    required String branch,
  }) async {
    branchReviewCalls++;
    lastBranchQuery = branch;
    final loader = branchReviewLoader;
    return loader == null ? branchReview : loader();
  }

  @override
  Future<HostedReview?> getReviewByNumber({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async => byNumber[number];

  @override
  Future<List<ReviewCheck>> getChecks({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    checksCalls++;
    final loader = checksLoader;
    return loader == null ? checks : loader();
  }

  @override
  Future<ReviewCheckDetails?> getCheckDetails({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewCheck check,
  }) async {
    lastDetailsNumber = number;
    lastDetailsCheck = check;
    return details;
  }

  @override
  Future<List<ReviewComment>> getReviewComments({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    commentsCalls++;
    final loader = commentsLoader;
    return loader == null ? comments : loader();
  }

  @override
  Future<void> addReviewComment({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required String body,
  }) async {
    addCommentCalls++;
    lastCommentBody = body;
    final error = addCommentError;
    if (error != null) {
      throw error;
    }
    comments = <ReviewComment>[
      ...comments,
      ReviewComment(
        id: 'new-$addCommentCalls',
        author: 'me',
        body: body,
        createdAt: DateTime.utc(2026, 7, 16),
        kind: ReviewCommentKind.conversation,
      ),
    ];
  }

  @override
  Future<CreateReviewResult> createReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required CreateReviewInput input,
  }) async {
    createCalls++;
    final error = createError;
    if (error != null) {
      throw error;
    }
    return createResult;
  }

  @override
  Future<UpdateReviewResult> updateReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required UpdateReviewInput input,
  }) async {
    updateCalls++;
    lastUpdateInput = input;
    final result = updateResult;
    if (result is UpdateReviewSuccess) {
      // Mutate the fake's world so the post-update reload sees the edit.
      byNumber[number] = result.review;
      if (branchReview?.number == number) {
        branchReview = result.review;
      }
    }
    return result;
  }

  @override
  Future<void> mergeReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required ReviewMergeMethod method,
  }) async {
    mergeCalls++;
    lastMergeMethod = method;
    final error = mergeError;
    if (error != null) {
      throw error;
    }
    _setReviewState(number, HostedReviewState.merged);
  }

  @override
  Future<void> closeReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
  }) async {
    closeCalls++;
    final error = closeError;
    if (error != null) {
      throw error;
    }
    _setReviewState(number, HostedReviewState.closed);
  }

  @override
  Future<void> setReviewDraft({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int number,
    required bool draft,
  }) async {
    draftStatusCalls++;
    lastDraftStatus = draft;
    final error = draftStatusError;
    if (error != null) {
      throw error;
    }
    _setReviewState(
      number,
      draft ? HostedReviewState.draft : HostedReviewState.open,
    );
  }

  void _setReviewState(int number, HostedReviewState state) {
    final current =
        byNumber[number] ??
        (branchReview?.number == number ? branchReview : null);
    if (current == null) {
      return;
    }
    final updated = current.copyWith(state: state);
    byNumber[number] = updated;
    if (branchReview?.number == number) {
      branchReview = updated;
    }
  }
}

/// In-memory [LinkedReviewRepository] keyed by workspace id.
class FakeLinkedReviewRepository implements LinkedReviewRepository {
  final Map<String, LinkedReview> store = <String, LinkedReview>{};

  @override
  Future<LinkedReview?> find(String workspaceId) async => store[workspaceId];

  @override
  Stream<LinkedReview?> watch(String workspaceId) async* {
    yield store[workspaceId];
  }

  @override
  Future<void> save(LinkedReview review) async {
    store[review.workspaceId] = review;
  }

  @override
  Future<void> remove(String workspaceId) async {
    store.remove(workspaceId);
  }
}
