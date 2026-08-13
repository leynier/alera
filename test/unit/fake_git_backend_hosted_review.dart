part of 'fake_git_backend.dart';

mixin _FakeGitBackendHostedReview {
  List<GitBackendCall> get calls;

  Future<GitHostedReviewRange> fetchHostedReviewRange({
    required String path,
    required String remote,
    required String baseBranch,
    required String headSha,
    String? reviewRef,
  }) async {
    calls.add(
      GitBackendCall('fetchHostedReviewRange', <String, Object?>{
        'path': path,
        'remote': remote,
        'baseBranch': baseBranch,
        'headSha': headSha,
        'reviewRef': reviewRef,
      }),
    );
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
}
