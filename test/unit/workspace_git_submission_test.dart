import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/features/workbench/application/workspace_git_submission.dart';
import 'package:alera/src/features/workbench/domain/workspace_git_quick_action.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git_backend.dart';

class _Git extends FakeGitBackend {
  int selectedCommits = 0;
  int pushes = 0;
  bool failPush = true;
  @override
  Future<String> commitSelected(
    String path,
    GitWorkspaceComparison snapshot,
    List<String> files,
    String message,
  ) async {
    selectedCommits++;
    expect(files, ['a.txt']);
    expect(message, 'reviewed message');
    comparisonResult = GitWorkspaceComparison(
      baseRef: snapshot.baseRef,
      baseOid: snapshot.baseOid,
      headOid: 'oid',
      headRef: snapshot.headRef,
      treeOid: snapshot.treeOid,
      indexOid: snapshot.indexOid,
      entries: snapshot.entries,
      added: snapshot.added,
      removed: snapshot.removed,
    );
    return 'oid';
  }

  @override
  Future<void> push(String path) async {
    pushes++;
    if (failPush) throw const GitCliException('network failed');
  }
}

void main() {
  test('PR retry preserves both the commit and successful push', () async {
    final git = _Git()..failPush = false;
    final submission = WorkspaceGitSubmission(
      path: '/repo',
      snapshot: await git.workspaceComparison('/repo'),
      action: WorkspaceGitQuickAction.commitPushPr,
      files: ['a.txt'],
      message: 'reviewed message',
      review: const CreateReviewInput(
        provider: GitHostingProvider.github,
        title: 'Reviewed PR',
        body: '',
        baseBranch: 'main',
        headBranch: 'feature',
        draft: true,
      ),
    );
    var reviews = 0;
    Future<CreateReviewResult> fail(input) async {
      reviews++;
      return const CreateReviewFailure(
        code: .unknown,
        message: 'forge unavailable',
      );
    }

    await expectLater(submission.run(git, fail), throwsStateError);
    await expectLater(submission.run(git, fail), throwsStateError);
    expect(git.selectedCommits, 1);
    expect(git.pushes, 1);
    expect(reviews, 2);
    expect(submission.completedSummary, contains('created and pushed'));
    expect(submission.pendingLabel, 'Retry Create PR');
  });
  test('retries a failed push without committing again', () async {
    final git = _Git();
    final snapshot = await git.workspaceComparison('/repo');
    final submission = WorkspaceGitSubmission(
      path: '/repo',
      snapshot: snapshot,
      action: WorkspaceGitQuickAction.commitPush,
      files: ['a.txt'],
      message: 'reviewed message',
    );
    Future<CreateReviewResult> unused(input) async =>
        throw StateError('unexpected PR');
    await expectLater(
      submission.run(git, unused),
      throwsA(isA<GitCliException>()),
    );
    expect(submission.commitCompleted, isTrue);
    expect(submission.pushCompleted, isFalse);
    expect(submission.completedSummary, contains('commit was created'));
    git.failPush = false;
    await submission.run(git, unused);
    expect(git.selectedCommits, 1);
    expect(git.pushes, 2);
    expect(submission.pushCompleted, isTrue);
  });
  test(
    'a refresh continuation never recreates an already created PR',
    () async {
      final git = _Git()..failPush = false;
      final submission = WorkspaceGitSubmission(
        path: '/repo',
        action: WorkspaceGitQuickAction.commitPushPr,
        snapshot: await git.workspaceComparison('/repo'),
        files: ['a.txt'],
        message: 'reviewed message',
        review: const CreateReviewInput(
          provider: .github,
          title: 'Details',
          baseBranch: 'main',
          headBranch: 'feature',
        ),
      );
      var creates = 0;
      Future<CreateReviewResult> create(CreateReviewInput input) async {
        creates++;
        return const CreateReviewSuccess(
          HostedReview(
            provider: .github,
            number: 123,
            title: 'Details',
            state: .open,
            url: '',
          ),
        );
      }

      await submission.run(git, create);
      await submission.run(git, create);
      expect(creates, 1);
      expect(git.selectedCommits, 1);
      expect(git.pushes, 1);
      expect(submission.completedSummary, contains('PR was created'));
    },
  );
}
