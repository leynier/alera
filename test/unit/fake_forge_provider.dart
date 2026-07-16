import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';

/// Configurable in-memory [ForgeProvider] shared by the pull-request
/// controller suites.
class FakeForgeProvider implements ForgeProvider {
  ForgeAuthStatus auth = ForgeAuthStatus.authenticated;
  HostedReview? branchReview;
  Future<HostedReview?> Function()? branchReviewLoader;
  int branchReviewCalls = 0;
  final Map<int, HostedReview> byNumber = <int, HostedReview>{};
  List<ReviewCheck> checks = <ReviewCheck>[];
  Future<List<ReviewCheck>> Function()? checksLoader;
  int checksCalls = 0;
  CreateReviewResult createResult = const CreateReviewFailure(
    code: CreateReviewErrorCode.unknown,
    message: 'not set',
  );
  int createCalls = 0;
  ReviewCheckDetails? details;
  ReviewCheck? lastDetailsCheck;
  int lastDetailsNumber = -1;
  UpdateReviewResult updateResult = const UpdateReviewFailure(
    code: UpdateReviewErrorCode.unknown,
    message: 'not set',
  );
  UpdateReviewInput? lastUpdateInput;
  int updateCalls = 0;

  @override
  GitHostingProvider get id => GitHostingProvider.github;

  @override
  bool get supportsReviewCreation => true;

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
  Future<CreateReviewResult> createReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required CreateReviewInput input,
  }) async {
    createCalls++;
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
