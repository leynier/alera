import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/infra/github_review_mappers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps the merge commit for a merged GitHub PR', () {
    final review = mapGitHubReview(<String, Object?>{
      'number': 124,
      'title': 'feat: merged',
      'state': 'MERGED',
      'url': 'https://github.com/leynier/alera/pull/124',
      'isDraft': false,
      'mergeable': 'UNKNOWN',
      'headRefName': 'feature',
      'baseRefName': 'main',
      'baseRefOid': 'base-abc',
      'headRefOid': 'def',
      'mergeCommit': <String, Object?>{'oid': 'merge-def'},
      'author': <String, Object?>{'login': 'leynier'},
    });

    expect(review.state, HostedReviewState.merged);
    expect(review.comparisonBaseSha, 'base-abc');
    expect(review.mergeCommitSha, 'merge-def');
  });
}
