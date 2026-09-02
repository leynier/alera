import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/forge_review_batch_provider.dart';
import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_monitor.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_summary.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_remote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'batches every workspace for one repository into one provider call',
    () async {
      final git = _FakeGitBackend();
      final forge = _FakeBatchForge(
        batch: ForgeReviewBatch(
          byBranch: <String, ForgeReviewSnapshot>{
            'feat/one': _snapshot(number: 1, branch: 'feat/one'),
            'feat/two': _snapshot(
              number: 2,
              branch: 'feat/two',
              checks: const <ReviewCheck>[_pendingCheck],
            ),
          },
        ),
      );
      final links = _FakeLinkedReviewRepository();
      final loader = WorkspacePullRequestMonitorLoader(
        git,
        ForgeProviderRegistry(<ForgeProvider>[forge]),
        links,
      );

      final result = await loader.load(
        targets: const <WorkspacePullRequestMonitorTarget>[
          WorkspacePullRequestMonitorTarget(
            projectId: 'project-a',
            projectName: 'Alera A',
            workspaceId: 'workspace-one',
            workspaceName: 'One',
            repoPath: '/repo',
            branch: 'feat/one',
          ),
          // A duplicate project registration for the same repository should not
          // launch a second gh process.
          WorkspacePullRequestMonitorTarget(
            projectId: 'project-b',
            projectName: 'Alera B',
            workspaceId: 'workspace-two',
            workspaceName: 'Two',
            repoPath: '/repo',
            branch: 'feat/two',
          ),
        ],
      );

      expect(result.hadErrors, isFalse);
      expect(result.summaries.keys, <String>['workspace-one', 'workspace-two']);
      expect(result.summaries['workspace-two']!.checksPending, isTrue);
      expect(git.listRemoteCalls, 1);
      expect(links.findCalls, 2);
      expect(forge.batchCalls, 1);
      expect(forge.authCalls, 0, reason: 'the batch classifies auth failures');
      expect(forge.lastBranches, <String>{'feat/one', 'feat/two'});
      expect(forge.lastReviewNumbers, isEmpty);
    },
  );

  test(
    'uses a manually linked review number instead of branch discovery',
    () async {
      final forge = _FakeBatchForge(
        batch: ForgeReviewBatch(
          byNumber: <int, ForgeReviewSnapshot>{
            77: _snapshot(number: 77, branch: 'remote-branch'),
          },
        ),
      );
      final links = _FakeLinkedReviewRepository(
        values: <String, LinkedReview>{
          'workspace': LinkedReview.linked(
            workspaceId: 'workspace',
            provider: .github,
            number: 77,
            url: 'https://github.com/acme/app/pull/77',
          ),
        },
      );
      final loader = WorkspacePullRequestMonitorLoader(
        _FakeGitBackend(),
        ForgeProviderRegistry(<ForgeProvider>[forge]),
        links,
      );

      final result = await loader.load(
        targets: const <WorkspacePullRequestMonitorTarget>[
          WorkspacePullRequestMonitorTarget(
            projectId: 'project',
            projectName: 'Alera',
            workspaceId: 'workspace',
            workspaceName: 'Workspace',
            repoPath: '/repo',
            branch: 'local-branch',
          ),
        ],
      );

      expect(result.summaries['workspace']!.review.number, 77);
      expect(forge.lastBranches, isEmpty);
      expect(forge.lastReviewNumbers, <int>{77});
    },
  );

  test(
    'preserves the last snapshot and reports provider errors for backoff',
    () async {
      final previous = <String, WorkspacePullRequestSummary>{
        'workspace': WorkspacePullRequestSummary.fromChecks(
          review: _review(number: 42, branch: 'feat/status'),
          checks: const <ReviewCheck>[_pendingCheck],
        ),
      };
      final forge = _FakeBatchForge(
        batch: const ForgeReviewBatch(),
        error: StateError('network unavailable'),
      );
      final loader = WorkspacePullRequestMonitorLoader(
        _FakeGitBackend(),
        ForgeProviderRegistry(<ForgeProvider>[forge]),
        _FakeLinkedReviewRepository(),
      );

      final result = await loader.load(
        targets: const <WorkspacePullRequestMonitorTarget>[
          WorkspacePullRequestMonitorTarget(
            projectId: 'project',
            projectName: 'Alera',
            workspaceId: 'workspace',
            workspaceName: 'Workspace',
            repoPath: '/repo',
            branch: 'feat/status',
          ),
        ],
        previous: previous,
      );

      expect(result.hadErrors, isTrue);
      expect(result.summaries['workspace'], previous['workspace']);
      expect(forge.batchCalls, 1);
    },
  );
}

const ReviewCheck _pendingCheck = ReviewCheck(
  name: 'build',
  status: .inProgress,
  conclusion: .pending,
);

ForgeReviewSnapshot _snapshot({
  required int number,
  required String branch,
  List<ReviewCheck> checks = const <ReviewCheck>[],
}) {
  return ForgeReviewSnapshot(
    review: _review(number: number, branch: branch),
    checks: checks,
  );
}

HostedReview _review({required int number, required String branch}) {
  return HostedReview(
    provider: .github,
    number: number,
    title: 'PR $number',
    state: .open,
    url: 'https://github.com/acme/app/pull/$number',
    headBranch: branch,
    headSha: 'sha-$number',
    mergeable: .mergeable,
  );
}

class _FakeGitBackend implements GitBackend {
  int listRemoteCalls = 0;

  @override
  Future<List<GitRemote>> listRemotes(String path) async {
    listRemoteCalls++;
    return const <GitRemote>[
      GitRemote(name: 'origin', url: 'git@github.com:acme/app.git'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLinkedReviewRepository implements LinkedReviewRepository {
  _FakeLinkedReviewRepository({Map<String, LinkedReview>? values})
    : _values = values ?? <String, LinkedReview>{};

  final Map<String, LinkedReview> _values;
  int findCalls = 0;

  @override
  Future<LinkedReview?> find(String workspaceId) async {
    findCalls++;
    return _values[workspaceId];
  }

  @override
  Future<void> remove(String workspaceId) async {
    _values.remove(workspaceId);
  }

  @override
  Future<void> save(LinkedReview review) async {
    _values[review.workspaceId] = review;
  }

  @override
  Stream<LinkedReview?> watch(String workspaceId) =>
      Stream<LinkedReview?>.value(_values[workspaceId]);
}

class _FakeBatchForge implements ForgeProvider, ForgeReviewBatchProvider {
  _FakeBatchForge({required this.batch, this.error});

  final ForgeReviewBatch batch;
  final Object? error;
  int batchCalls = 0;
  int authCalls = 0;
  Set<String> lastBranches = const <String>{};
  Set<int> lastReviewNumbers = const <int>{};

  @override
  GitHostingProvider get id => GitHostingProvider.github;

  @override
  Future<ForgeAuthStatus> checkAuth({
    required GitRemoteIdentity identity,
  }) async {
    authCalls++;
    return ForgeAuthStatus.authenticated;
  }

  @override
  Future<ForgeReviewBatch> getReviewBatch({
    required GitRemoteIdentity identity,
    required String repoPath,
    required Set<String> branches,
    required Set<int> reviewNumbers,
  }) async {
    batchCalls++;
    lastBranches = Set<String>.from(branches);
    lastReviewNumbers = Set<int>.from(reviewNumbers);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return batch;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
