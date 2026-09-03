import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_ship_scope.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';
import 'workspace_pull_request_ship_support.dart';

void main() {
  test('stages all changes before shipping when scope is all', () async {
    const headBranch = 'feat/ship-all';
    final git = FakeGitBackend()
      ..headBranch = headBranch
      ..sourceBranches = <String>['main', headBranch]
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      }
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(path: 'README.md', area: .unstaged, status: .modified),
        ],
      );
    final review = shipTestReview(705, headBranch: headBranch);
    final forge = FakeForgeProvider()
      ..createResult = CreateReviewSuccess(review)
      ..byNumber[705] = review;
    final aiAssist = FakeShipAiAssistService(<Object>[
      const AiAssistResult(text: 'feat: ship all changes', agentLabel: 'Codex'),
      const AiAssistResult(
        text: 'Ship all changes\n\nStage everything first.',
        agentLabel: 'Codex',
      ),
    ]);
    final container = createShipTestContainer(
      git: git,
      forge: forge,
      linkedReviews: FakeLinkedReviewRepository(),
      aiAssist: aiAssist,
    );
    addTearDown(container.dispose);
    await container.read(
      workspacePullRequestControllerProvider(shipTestScope).future,
    );

    final result = await container
        .read(workspacePullRequestControllerProvider(shipTestScope).notifier)
        .ship(
          baseBranch: 'main',
          draft: false,
          settings: AiAssistSettings.defaults,
          scope: PullRequestShipScope.all,
        );

    expect(result, isA<CreateReviewSuccess>());
    final methods = git.calls.map((call) => call.method).toList();
    expect(methods, contains('stage'));
    expect(methods.indexOf('stage'), lessThan(methods.indexOf('commit')));
    expect(forge.lastCreateInput?.headBranch, headBranch);
  });

  test('blocks Ship All when there are no changes at all', () async {
    final git = FakeGitBackend()
      ..headBranch = 'feat/ship-all'
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      }
      ..gitStatusResult = const GitStatusResult(entries: []);
    final forge = FakeForgeProvider();
    final aiAssist = FakeShipAiAssistService(const <Object>[]);
    final container = createShipTestContainer(
      git: git,
      forge: forge,
      linkedReviews: FakeLinkedReviewRepository(),
      aiAssist: aiAssist,
    );
    addTearDown(container.dispose);
    await container.read(
      workspacePullRequestControllerProvider(shipTestScope).future,
    );

    final result = await container
        .read(workspacePullRequestControllerProvider(shipTestScope).notifier)
        .ship(
          baseBranch: 'main',
          draft: false,
          settings: AiAssistSettings.defaults,
          scope: PullRequestShipScope.all,
        );

    expect(result, isA<CreateReviewFailure>());
    expect((result as CreateReviewFailure).message, 'No changes to ship.');
    expect(aiAssist.requests, isEmpty);
    expect(git.calls.where((call) => call.method == 'stage'), isEmpty);
    expect(git.calls.where((call) => call.method == 'commit'), isEmpty);
  });
}
