import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/forge_stack_provider.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/review_stack_workspace_models.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';

part 'workspace_pull_request_stack_workspace_test_fakes.dart';

const _scope = WorkspacePullRequestScope(
  workspaceId: 'workspace-two',
  repoPath: '/repo-two',
  branch: 'feature/two',
);

const _remote = <String, String?>{
  'origin': 'https://github.com/leynier/alera.git',
};

HostedReview _review(
  int number, {
  required String branch,
  required String baseBranch,
}) {
  return HostedReview(
    provider: .github,
    number: number,
    title: 'feat: layer $number',
    state: .open,
    url: 'https://github.com/leynier/alera/pull/$number',
    headBranch: branch,
    baseBranch: baseBranch,
  );
}

ReviewStackWorkspaceLayerInput _layer({
  required String workspaceId,
  required String repoPath,
  required String branch,
  String? title,
  String? body,
  bool draft = false,
}) {
  return ReviewStackWorkspaceLayerInput(
    workspaceId: workspaceId,
    repoPath: repoPath,
    branch: branch,
    title: title ?? branch,
    body: body,
    draft: draft,
  );
}

FakeGitBackend _git(Map<String, String> branchesByPath) {
  return FakeGitBackend()
    ..headBranch = 'feature/two'
    ..remotesByName = _remote
    ..currentBranchesByPath.addAll(branchesByPath);
}

ProviderContainer _container({
  required _WorkspaceStackForgeProvider forge,
  required FakeGitBackend git,
  required FakeLinkedReviewRepository linkedReviews,
}) {
  final container = ProviderContainer(
    overrides: [
      gitBackendProvider.overrideWithValue(git),
      forgeProviderRegistryProvider.overrideWithValue(
        ForgeProviderRegistry(<ForgeProvider>[forge]),
      ),
      linkedReviewRepositoryProvider.overrideWithValue(linkedReviews),
    ],
  );
  container.listen(workspacePullRequestControllerProvider(_scope), (_, _) {});
  container
      .read(workspacePullRequestControllerProvider(_scope).notifier)
      .attachPanel();
  return container;
}

Future<void> _load(ProviderContainer container) {
  return container.read(workspacePullRequestControllerProvider(_scope).future);
}

void main() {
  test(
    'creates a stack when the current workspace has no pull request',
    () async {
      final first = _review(41, branch: 'feature/one', baseBranch: 'main');
      final current = _review(
        42,
        branch: 'feature/two',
        baseBranch: 'feature/one',
      );
      final forge = _WorkspaceStackForgeProvider()
        ..branchReviews['feature/one'] = null
        ..branchReviews['feature/two'] = null
        ..createResults.addAll(<CreateReviewResult>[
          CreateReviewSuccess(first),
          CreateReviewSuccess(current),
        ]);
      final git = _git(<String, String>{
        '/repo-one': 'feature/one',
        '/repo-two': 'feature/two',
      });
      final linked = FakeLinkedReviewRepository();
      final container = _container(
        forge: forge,
        git: git,
        linkedReviews: linked,
      );
      addTearDown(container.dispose);

      final initial = await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      expect(initial.review, isNull);
      expect(initial.stackSupported, isTrue);

      await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .createReviewStackFromWorkspaces(
            ReviewStackWorkspaceRequest(
              baseBranch: 'main',
              layers: <ReviewStackWorkspaceLayerInput>[
                _layer(
                  workspaceId: 'workspace-one',
                  repoPath: '/repo-one',
                  branch: 'feature/one',
                  title: 'feat: first layer',
                ),
                _layer(
                  workspaceId: 'workspace-two',
                  repoPath: '/repo-two',
                  branch: 'feature/two',
                  title: 'feat: second layer',
                ),
              ],
            ),
          );

      expect(forge.createInputs, hasLength(2));
      expect(forge.createInputs[0].baseBranch, 'main');
      expect(forge.createInputs[0].headBranch, 'feature/one');
      expect(forge.createInputs[1].baseBranch, 'feature/one');
      expect(forge.createInputs[1].headBranch, 'feature/two');
      expect(forge.linkedReviewNumbers, <int>[41, 42]);
      expect(linked.store['workspace-one']?.number, 41);
      expect(linked.store['workspace-two']?.number, 42);

      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(state.review?.number, 42);
      expect(state.stack?.entries.map((entry) => entry.review.number), <int>[
        41,
        42,
      ]);
    },
  );

  test('reuses open PRs and creates only missing workspace PRs', () async {
    final first = _review(41, branch: 'feature/one', baseBranch: 'main');
    final current = _review(
      42,
      branch: 'feature/two',
      baseBranch: 'feature/one',
    );
    final forge = _WorkspaceStackForgeProvider()
      ..branchReviews['feature/one'] = null
      ..branchReviews['feature/two'] = current
      ..createResults.add(CreateReviewSuccess(first));
    forge.byNumber[42] = current;
    final git = _git(<String, String>{
      '/repo-one': 'feature/one',
      '/repo-two': 'feature/two',
    });
    final linked = FakeLinkedReviewRepository();
    final container = _container(forge: forge, git: git, linkedReviews: linked);
    addTearDown(container.dispose);

    await _load(container);
    await container
        .read(workspacePullRequestControllerProvider(_scope).notifier)
        .createReviewStackFromWorkspaces(
          ReviewStackWorkspaceRequest(
            baseBranch: 'main',
            layers: <ReviewStackWorkspaceLayerInput>[
              _layer(
                workspaceId: 'workspace-one',
                repoPath: '/repo-one',
                branch: 'feature/one',
                title: 'feat: first layer',
                body: 'First body',
                draft: true,
              ),
              _layer(
                workspaceId: 'workspace-two',
                repoPath: '/repo-two',
                branch: 'feature/two',
              ),
            ],
          ),
        );

    expect(forge.createInputs, hasLength(1));
    final input = forge.createInputs.single;
    expect(input.baseBranch, 'main');
    expect(input.headBranch, 'feature/one');
    expect(input.title, 'feat: first layer');
    expect(input.body, 'First body');
    expect(input.draft, isTrue);
    expect(forge.createRepoPaths.single, '/repo-one');
    expect(forge.linkedReviewNumbers, <int>[41, 42]);
    expect(forge.linkedStackNumber, isNull);
    expect(forge.linkedBaseBranch, 'main');
    expect(linked.store['workspace-one']?.number, 41);
    expect(linked.store['workspace-two']?.number, 42);
    expect(
      git.calls
          .where((call) => call.method == 'push')
          .map((call) => call.args['path']),
      <Object?>['/repo-one', '/repo-two'],
    );
    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.errorMessage, isNull);
    expect(state.stack?.entries.map((entry) => entry.review.number), <int>[
      41,
      42,
    ]);
  });

  test(
    'appends a missing workspace PR to the top of an existing stack',
    () async {
      final first = _review(41, branch: 'feature/one', baseBranch: 'main');
      final current = _review(
        42,
        branch: 'feature/two',
        baseBranch: 'feature/one',
      );
      final third = _review(
        43,
        branch: 'feature/three',
        baseBranch: 'feature/two',
      );
      final existingStack = HostedReviewStack(
        number: 700,
        baseBranch: 'main',
        open: true,
        entries: <HostedReviewStackEntry>[
          HostedReviewStackEntry(review: first, position: 1),
          HostedReviewStackEntry(review: current, position: 2),
        ],
      );
      final forge = _WorkspaceStackForgeProvider()
        ..stack = existingStack
        ..branchReviews['feature/two'] = current
        ..branchReviews['feature/three'] = null
        ..createResults.add(CreateReviewSuccess(third));
      forge.byNumber
        ..[41] = first
        ..[42] = current;
      final git = _git(<String, String>{
        '/repo-two': 'feature/two',
        '/repo-three': 'feature/three',
      });
      final linked = FakeLinkedReviewRepository();
      final container = _container(
        forge: forge,
        git: git,
        linkedReviews: linked,
      );
      addTearDown(container.dispose);

      await _load(container);
      await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .createReviewStackFromWorkspaces(
            ReviewStackWorkspaceRequest(
              baseBranch: 'main',
              layers: <ReviewStackWorkspaceLayerInput>[
                _layer(
                  workspaceId: 'workspace-three',
                  repoPath: '/repo-three',
                  branch: 'feature/three',
                  title: 'feat: third layer',
                ),
              ],
            ),
          );

      expect(forge.createInputs.single.baseBranch, 'feature/two');
      expect(forge.linkedReviewNumbers, <int>[43]);
      expect(forge.linkedStackNumber, 700);
      expect(forge.linkedBaseBranch, isNull);
      expect(linked.store['workspace-three']?.number, 43);
      expect(forge.stack?.entries.map((entry) => entry.review.number), <int>[
        41,
        42,
        43,
      ]);
    },
  );

  test(
    'keeps completed workspace links when a later PR creation fails',
    () async {
      final current = _review(42, branch: 'feature/two', baseBranch: 'main');
      final forge = _WorkspaceStackForgeProvider()
        ..branchReviews['feature/two'] = current
        ..branchReviews['feature/three'] = null
        ..createResults.add(
          const CreateReviewFailure(
            code: .blocked,
            message: 'permission denied',
          ),
        );
      forge.byNumber[42] = current;
      final git = _git(<String, String>{
        '/repo-two': 'feature/two',
        '/repo-three': 'feature/three',
      });
      final linked = FakeLinkedReviewRepository();
      final container = _container(
        forge: forge,
        git: git,
        linkedReviews: linked,
      );
      addTearDown(container.dispose);

      await _load(container);
      await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .createReviewStackFromWorkspaces(
            ReviewStackWorkspaceRequest(
              baseBranch: 'main',
              layers: <ReviewStackWorkspaceLayerInput>[
                _layer(
                  workspaceId: 'workspace-two',
                  repoPath: '/repo-two',
                  branch: 'feature/two',
                ),
                _layer(
                  workspaceId: 'workspace-three',
                  repoPath: '/repo-three',
                  branch: 'feature/three',
                ),
              ],
            ),
          );

      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(state.errorMessage, contains('permission denied'));
      expect(state.action, isNull);
      expect(linked.store['workspace-two']?.number, 42);
      expect(linked.store.containsKey('workspace-three'), isFalse);
      expect(forge.linkStackCalls, 0);
      expect(git.calls.where((call) => call.method == 'push'), hasLength(2));
    },
  );

  test(
    'rejects a workspace from another repository before side effects',
    () async {
      final current = _review(42, branch: 'feature/two', baseBranch: 'main');
      final forge = _WorkspaceStackForgeProvider()
        ..branchReviews['feature/two'] = current;
      forge.byNumber[42] = current;
      final git =
          _git(<String, String>{
              '/repo-two': 'feature/two',
              '/other-three': 'feature/three',
            })
            ..remotesByPath['/other-three'] = <String, String?>{
              'origin': 'https://github.com/other/repository.git',
            };
      final linked = FakeLinkedReviewRepository();
      final container = _container(
        forge: forge,
        git: git,
        linkedReviews: linked,
      );
      addTearDown(container.dispose);

      await _load(container);
      await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .createReviewStackFromWorkspaces(
            ReviewStackWorkspaceRequest(
              baseBranch: 'main',
              layers: <ReviewStackWorkspaceLayerInput>[
                _layer(
                  workspaceId: 'workspace-two',
                  repoPath: '/repo-two',
                  branch: 'feature/two',
                ),
                _layer(
                  workspaceId: 'workspace-three',
                  repoPath: '/other-three',
                  branch: 'feature/three',
                ),
              ],
            ),
          );

      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(state.errorMessage, contains('does not belong'));
      expect(forge.createInputs, isEmpty);
      expect(forge.linkStackCalls, 0);
      expect(linked.store, isEmpty);
      expect(git.calls.where((call) => call.method == 'push'), isEmpty);
    },
  );

  test('rejects a stale workspace branch before remote mutations', () async {
    final current = _review(42, branch: 'feature/two', baseBranch: 'main');
    final forge = _WorkspaceStackForgeProvider()
      ..branchReviews['feature/two'] = current;
    forge.byNumber[42] = current;
    final git = _git(<String, String>{
      '/repo-two': 'feature/two',
      '/repo-three': 'feature/wrong',
    });
    final linked = FakeLinkedReviewRepository();
    final container = _container(forge: forge, git: git, linkedReviews: linked);
    addTearDown(container.dispose);

    await _load(container);
    await container
        .read(workspacePullRequestControllerProvider(_scope).notifier)
        .createReviewStackFromWorkspaces(
          ReviewStackWorkspaceRequest(
            baseBranch: 'main',
            layers: <ReviewStackWorkspaceLayerInput>[
              _layer(
                workspaceId: 'workspace-two',
                repoPath: '/repo-two',
                branch: 'feature/two',
              ),
              _layer(
                workspaceId: 'workspace-three',
                repoPath: '/repo-three',
                branch: 'feature/three',
              ),
            ],
          ),
        );

    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.errorMessage, contains('currently checked out'));
    expect(state.errorMessage, contains('feature/wrong'));
    expect(forge.createInputs, isEmpty);
    expect(forge.linkStackCalls, 0);
    expect(linked.store, isEmpty);
    expect(git.calls.where((call) => call.method == 'push'), isEmpty);
  });
}
