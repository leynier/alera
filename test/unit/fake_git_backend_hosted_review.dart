part of 'fake_git_backend.dart';

mixin _FakeGitBackendHostedReview {
  List<GitBackendCall> get calls;

  Completer<void>? fetchHostedReviewRangeGate;

  Future<GitHostedReviewRange> fetchHostedReviewRange({
    required String path,
    required String remote,
    required String baseBranch,
    required String headSha,
    String? headRemote,
    String? comparisonBaseSha,
    String? mergeCommitSha,
    String? reviewRef,
  }) async {
    calls.add(
      GitBackendCall('fetchHostedReviewRange', <String, Object?>{
        'path': path,
        'remote': remote,
        'baseBranch': baseBranch,
        'headSha': headSha,
        'headRemote': headRemote,
        'comparisonBaseSha': comparisonBaseSha,
        'mergeCommitSha': mergeCommitSha,
        'reviewRef': reviewRef,
      }),
    );
    final gate = fetchHostedReviewRangeGate;
    if (gate != null && !gate.isCompleted) {
      fetchHostedReviewRangeGate = null;
      await gate.future;
    }
    return GitHostedReviewRange(
      baseOid: baseBranch,
      headOid: headSha,
      retentionId: '00000000000000000000000000000001',
    );
  }

  Future<void> releaseHostedReviewRange({
    required String path,
    required String retentionId,
  }) async {
    calls.add(
      GitBackendCall('releaseHostedReviewRange', <String, Object?>{
        'path': path,
        'retentionId': retentionId,
      }),
    );
  }

  Object? persistHostedReviewRangeError;
  Completer<void>? persistHostedReviewRangeGate;

  Future<void> persistHostedReviewRange({
    required String path,
    required String retentionId,
  }) async {
    calls.add(
      GitBackendCall('persistHostedReviewRange', <String, Object?>{
        'path': path,
        'retentionId': retentionId,
      }),
    );
    final gate = persistHostedReviewRangeGate;
    if (gate != null && !gate.isCompleted) {
      persistHostedReviewRangeGate = null;
      await gate.future;
    }
    if (persistHostedReviewRangeError case final Object error) {
      throw error;
    }
  }
}
