import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';

const _scope = WorkspacePullRequestScope(
  workspaceId: 'workspace-1',
  repoPath: '/repo',
  branch: 'main',
);

HostedReview _review(int number, {required String headBranch}) => HostedReview(
  provider: .github,
  number: number,
  title: 'feat: shipped changes',
  state: .open,
  url: 'https://github.com/leynier/alera/pull/$number',
  headBranch: headBranch,
  baseBranch: 'main',
);

ProviderContainer _container({
  required FakeGitBackend git,
  required FakeForgeProvider forge,
  required FakeLinkedReviewRepository linkedReviews,
  required AiAssistService aiAssist,
}) {
  final container = ProviderContainer(
    overrides: [
      gitBackendProvider.overrideWithValue(git),
      aiAssistServiceProvider.overrideWithValue(aiAssist),
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

void main() {
  test('ships staged changes from main on a new available branch', () async {
    const headBranch = 'ship/add-ship-action-2';
    final git = FakeGitBackend()
      ..headBranch = 'main'
      ..sourceBranches = <String>['main', 'ship/add-ship-action']
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      }
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/ship.dart',
            area: .staged,
            status: .modified,
          ),
          GitChangeEntry(path: 'README.md', area: .unstaged, status: .modified),
        ],
      );
    final review = _review(701, headBranch: headBranch);
    final forge = FakeForgeProvider()
      ..createResult = CreateReviewSuccess(review)
      ..byNumber[701] = review;
    final linkedReviews = FakeLinkedReviewRepository();
    final aiAssist = _FakeAiAssistService(<Object>[
      const AiAssistResult(
        text: 'feat: add ship action\n\nCommit only staged changes.',
        agentLabel: 'Codex',
      ),
      const AiAssistResult(
        text: 'Add one-click Ship action\n\nCommits staged changes and opens a PR.',
        agentLabel: 'Codex',
      ),
    ]);
    final container = _container(
      git: git,
      forge: forge,
      linkedReviews: linkedReviews,
      aiAssist: aiAssist,
    );
    addTearDown(container.dispose);
    await container.read(workspacePullRequestControllerProvider(_scope).future);

    final result = await container
        .read(workspacePullRequestControllerProvider(_scope).notifier)
        .ship(
          baseBranch: 'main',
          draft: false,
          settings: AiAssistSettings.defaults,
        );

    expect(result, isA<CreateReviewSuccess>());
    final methods = git.calls.map((call) => call.method).toList();
    expect(
      methods,
      containsAll(<String>[
        'status',
        'createAndCheckoutBranch',
        'commit',
        'push',
      ]),
    );
    expect(
      methods.indexOf('createAndCheckoutBranch'),
      lessThan(methods.indexOf('commit')),
    );
    final branchCall = git.calls.singleWhere(
      (call) => call.method == 'createAndCheckoutBranch',
    );
    expect(branchCall.args['branch'], headBranch);
    final commitCall = git.calls.singleWhere((call) => call.method == 'commit');
    expect(
      commitCall.args['message'],
      'feat: add ship action\n\nCommit only staged changes.',
    );
    expect(
      aiAssist.requests.map((request) => request.operation),
      <AiAssistOperation>[
        AiAssistOperation.commitMessage,
        AiAssistOperation.pullRequestDetails,
      ],
    );
    expect(forge.lastCreateInput?.headBranch, headBranch);
    expect(forge.lastCreateInput?.baseBranch, 'main');
    expect(forge.lastCreateInput?.title, 'Add one-click Ship action');
    expect(forge.lastCreateInput?.draft, isFalse);
    expect(linkedReviews.store['workspace-1']?.number, 701);
    final state = container
        .read(workspacePullRequestControllerProvider(_scope))
        .value!;
    expect(state.currentBranch, headBranch);
    expect(state.review?.number, 701);
  });

  test(
    'ships directly from a feature branch and falls back to commit text',
    () async {
      const headBranch = 'feat/already-started';
      final git = FakeGitBackend()
        ..headBranch = headBranch
        ..sourceBranches = <String>['main', headBranch]
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        }
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/feature.dart',
              area: .staged,
              status: .added,
            ),
          ],
        );
      final review = _review(702, headBranch: headBranch);
      final forge = FakeForgeProvider()
        ..createResult = CreateReviewSuccess(review)
        ..byNumber[702] = review;
      final aiAssist = _FakeAiAssistService(<Object>[
        const AiAssistResult(
          text: 'fix: keep staged scope\n\nDo not include unstaged files.',
          agentLabel: 'Claude Code',
        ),
        const AiAssistException('PR detail generation failed.'),
      ]);
      final container = _container(
        git: git,
        forge: forge,
        linkedReviews: FakeLinkedReviewRepository(),
        aiAssist: aiAssist,
      );
      addTearDown(container.dispose);
      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );

      final result = await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .ship(
            baseBranch: 'main',
            draft: true,
            settings: AiAssistSettings.defaults,
          );

      expect(result, isA<CreateReviewSuccess>());
      expect(
        git.calls.where((call) => call.method == 'createAndCheckoutBranch'),
        isEmpty,
      );
      expect(forge.lastCreateInput?.headBranch, headBranch);
      expect(forge.lastCreateInput?.title, 'fix: keep staged scope');
      expect(forge.lastCreateInput?.body, 'Do not include unstaged files.');
      expect(forge.lastCreateInput?.draft, isTrue);
    },
  );

  test(
    'keeps the new branch visible when PR creation fails after commit',
    () async {
      const headBranch = 'ship/add-ship-action';
      final git = FakeGitBackend()
        ..headBranch = 'main'
        ..sourceBranches = <String>['main']
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        }
        ..pushError = const GitInternalException('network unavailable')
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/ship.dart',
              area: .staged,
              status: .modified,
            ),
          ],
        );
      final forge = FakeForgeProvider();
      final aiAssist = _FakeAiAssistService(<Object>[
        const AiAssistResult(
          text: 'feat: add ship action',
          agentLabel: 'Codex',
        ),
        const AiAssistResult(
          text: 'Add Ship action\n\nCreate a PR from staged changes.',
          agentLabel: 'Codex',
        ),
      ]);
      final container = _container(
        git: git,
        forge: forge,
        linkedReviews: FakeLinkedReviewRepository(),
        aiAssist: aiAssist,
      );
      addTearDown(container.dispose);
      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );

      final result = await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .ship(
            baseBranch: 'main',
            draft: false,
            settings: AiAssistSettings.defaults,
          );

      expect(result, isA<CreateReviewFailure>());
      final failure = result as CreateReviewFailure;
      expect(failure.code, CreateReviewErrorCode.pushFailed);
      expect(
        failure.message,
        'The staged changes were committed, but Ship could not finish: '
        'Could not push the branch: network unavailable',
      );
      expect(forge.createCalls, 0);
      expect(git.calls.where((call) => call.method == 'commit'), hasLength(1));
      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(state.currentBranch, headBranch);
      expect(state.errorMessage, failure.message);
    },
  );

  test(
    'blocks Ship before AI or git mutations when nothing is staged',
    () async {
      final git = FakeGitBackend()
        ..headBranch = 'main'
        ..remotesByName = <String, String?>{
          'origin': 'https://github.com/leynier/alera.git',
        }
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'README.md',
              area: .unstaged,
              status: .modified,
            ),
          ],
        );
      final forge = FakeForgeProvider();
      final aiAssist = _FakeAiAssistService(const <Object>[]);
      final container = _container(
        git: git,
        forge: forge,
        linkedReviews: FakeLinkedReviewRepository(),
        aiAssist: aiAssist,
      );
      addTearDown(container.dispose);
      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );

      final result = await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .ship(
            baseBranch: 'main',
            draft: false,
            settings: AiAssistSettings.defaults,
          );

      expect(result, isA<CreateReviewFailure>());
      expect(
        (result as CreateReviewFailure).code,
        CreateReviewErrorCode.blocked,
      );
      expect(result.message, 'Stage at least one change before shipping.');
      expect(aiAssist.requests, isEmpty);
      expect(forge.createCalls, 0);
      expect(
        git.calls.where(
          (call) => <String>{
            'createAndCheckoutBranch',
            'commit',
            'push',
          }.contains(call.method),
        ),
        isEmpty,
      );
      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(state.errorMessage, 'Stage at least one change before shipping.');
    },
  );
}

class _FakeAiAssistService implements AiAssistService {
  _FakeAiAssistService(List<Object> responses)
    : _responses = List<Object>.of(responses);

  final List<Object> _responses;
  final List<AiAssistRequest> requests = <AiAssistRequest>[];

  @override
  Future<AiAssistResult> generate(AiAssistRequest request) async {
    requests.add(request);
    final response = _responses.removeAt(0);
    if (response is AiAssistException) {
      throw response;
    }
    return response as AiAssistResult;
  }

  @override
  void cancel(String workspacePath, AiAssistOperation operation) {}
}
