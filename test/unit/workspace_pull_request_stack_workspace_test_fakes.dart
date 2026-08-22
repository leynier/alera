part of 'workspace_pull_request_stack_workspace_controller_test.dart';

class _WorkspaceStackForgeProvider extends FakeForgeProvider
    implements ForgeStackProvider {
  final Map<String, HostedReview?> branchReviews = <String, HostedReview?>{};
  final List<CreateReviewResult> createResults = <CreateReviewResult>[];
  final List<CreateReviewInput> createInputs = <CreateReviewInput>[];
  final List<String> createRepoPaths = <String>[];
  HostedReviewStack? stack;
  int linkStackCalls = 0;
  List<int>? linkedReviewNumbers;
  int? linkedStackNumber;
  String? linkedBaseBranch;

  @override
  Future<HostedReview?> getReviewForBranch({
    required GitRemoteIdentity identity,
    required String repoPath,
    required String branch,
  }) async {
    branchReviewCalls++;
    lastBranchQuery = branch;
    if (branchReviews.containsKey(branch)) {
      return branchReviews[branch];
    }
    return branchReview;
  }

  @override
  Future<CreateReviewResult> createReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required CreateReviewInput input,
  }) async {
    createCalls++;
    createInputs.add(input);
    createRepoPaths.add(repoPath);
    final result = createResults.isEmpty
        ? createResult
        : createResults.removeAt(0);
    if (result is CreateReviewSuccess) {
      branchReviews[input.headBranch] = result.review;
      byNumber[result.review.number] = result.review;
    }
    return result;
  }

  @override
  Future<HostedReviewStack?> getStackForReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int reviewNumber,
  }) async => stack;

  @override
  Future<HostedReviewStack> linkReviewStack({
    required GitRemoteIdentity identity,
    required String repoPath,
    required List<int> reviewNumbers,
    int? stackNumber,
    String? baseBranch,
  }) async {
    linkStackCalls++;
    linkedReviewNumbers = List<int>.from(reviewNumbers);
    linkedStackNumber = stackNumber;
    linkedBaseBranch = baseBranch;
    final newReviews = reviewNumbers
        .map((number) => byNumber[number]!)
        .toList();
    final existingReviews = stackNumber == null
        ? const <HostedReview>[]
        : stack?.entries.map((entry) => entry.review).toList() ??
              const <HostedReview>[];
    final reviews = <HostedReview>[...existingReviews, ...newReviews];
    stack = HostedReviewStack(
      number: stackNumber ?? 700,
      baseBranch: baseBranch ?? stack?.baseBranch ?? 'main',
      open: true,
      entries: <HostedReviewStackEntry>[
        for (final (index, review) in reviews.indexed)
          HostedReviewStackEntry(review: review, position: index + 1),
      ],
    );
    return stack!;
  }

  @override
  Future<void> mergeReviewStack({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int reviewNumber,
    required ReviewMergeMethod method,
  }) async {}
}
