import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('constructs create review input with defaults', () {
    final input = CreateReviewInput(
      provider: GitHostingProvider.github,
      title: 'feat: coverage',
      baseBranch: 'main',
      headBranch: 'feature',
    );

    expect(input.provider, GitHostingProvider.github);
    expect(input.title, 'feat: coverage');
    expect(input.baseBranch, 'main');
    expect(input.headBranch, 'feature');
    expect(input.body, isNull);
    expect(input.draft, isFalse);
  });

  test('round-trips mapped pull request domain models', () {
    const identity = GitRemoteIdentity(
      provider: GitHostingProvider.azureDevops,
      host: 'dev.azure.com',
      owner: 'org',
      repo: 'repo',
      project: 'project',
    );
    const review = HostedReview(
      provider: GitHostingProvider.github,
      number: 42,
      title: 'Coverage',
      state: HostedReviewState.open,
      url: 'https://example.test/pull/42',
      mergeable: HostedReviewMergeable.mergeable,
    );
    const check = ReviewCheck(
      name: 'flutter',
      status: ReviewCheckStatus.completed,
      conclusion: ReviewCheckConclusion.success,
      url: 'https://example.test/check',
    );

    expect(GitRemoteIdentity.fromJson(identity.toMap()), identity);
    expect(HostedReview.fromJson(review.toMap()), review);
    expect(ReviewCheck.fromJson(check.toMap()), check);
    expect(review.isOpen, isTrue);
    expect(review.copyWith(state: HostedReviewState.draft).isOpen, isTrue);
    expect(review.copyWith(state: HostedReviewState.closed).isOpen, isFalse);
  });
}
