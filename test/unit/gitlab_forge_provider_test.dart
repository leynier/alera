import 'dart:io';

import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/infra/gitlab_forge_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_process_runner.dart';

const _identity = GitRemoteIdentity(
  provider: GitHostingProvider.gitlab,
  host: 'gitlab.acme.test:8443',
  owner: 'platform/mobile',
  repo: 'alera',
);

ProcessRunOutput _ok(String stdout) =>
    ProcessRunOutput(exitCode: 0, stdout: stdout, stderr: '');

const _reviewJson = '''
{"iid":42,"title":"feat: gitlab","state":"opened","draft":false,"web_url":"https://gitlab.acme.test:8443/platform/mobile/alera/-/merge_requests/42","created_at":"2026-07-20T12:00:00Z","author":{"username":"alice"},"target_branch":"main","source_branch":"feature","sha":"abc","diff_refs":{"base_sha":"base-abc"},"detailed_merge_status":"mergeable","has_conflicts":false}
''';

void main() {
  group('GitLabForgeProvider reads', () {
    test('finds and maps an MR for a branch through glab api', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok(_reviewJson)]);
      final provider = GitLabForgeProvider(runner);

      final review = await provider.getReviewForBranch(
        identity: _identity,
        repoPath: '/repo',
        branch: 'feature/test',
      );

      expect(review!.number, 42);
      expect(review.provider, GitHostingProvider.gitlab);
      expect(review.author, 'alice');
      expect(review.state, HostedReviewState.open);
      expect(review.mergeable, HostedReviewMergeable.mergeable);
      expect(review.comparisonBaseSha, 'base-abc');
      final call = runner.calls.single;
      expect(call.executable, 'glab');
      expect(call.arguments.first, 'api');
      expect(call.arguments[1], contains('projects/platform%2Fmobile%2Falera'));
      expect(call.arguments[1], contains('source_branch=feature%2Ftest'));
      expect(call.arguments, isNot(contains('--hostname')));
      expect(call.arguments, contains('--paginate'));
      expect(call.optionValue('output'), 'ndjson');
      expect(call.environment?['GITLAB_REPO'], _repoUrl);
      expect(call.workingDirectory, '/repo');
    });

    test('flattens paginated NDJSON responses', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
${_reviewJson.replaceFirst('"iid":42', '"iid":41').replaceFirst('2026-07-20T12:00:00Z', '2026-07-19T12:00:00Z').trim()}
${_reviewJson.trim()}
'''),
      ]);

      final review = await GitLabForgeProvider(runner).getReviewForBranch(
        identity: _identity,
        repoPath: '/repo',
        branch: 'feature',
      );

      expect(review?.number, 42);
      expect(runner.calls.single.optionValue('output'), 'ndjson');
    });

    test(
      'does not classify successful response text as a missing CLI',
      () async {
        final runner = FakeRecordingProcessRunner(<Object>[
          _ok(_reviewJson.replaceFirst('feat: gitlab', 'no such file')),
        ]);

        final review = await GitLabForgeProvider(
          runner,
        ).getReviewByNumber(identity: _identity, repoPath: '/repo', number: 42);

        expect(review?.title, 'no such file');
      },
    );

    test('maps MR pipelines to checks and details', () async {
      const headPipeline = '''
{"head_pipeline":{"id":99,"status":"success","ref":"refs/merge-requests/42/head","sha":"abc","web_url":"https://gitlab.acme.test:8443/pipelines/99"}}
''';
      const pipelineDetails = '''
{"id":99,"status":"success","ref":"refs/merge-requests/42/head","sha":"abc","source":"merge_request_event","created_at":"2026-07-20T12:01:00Z","started_at":"2026-07-20T12:02:00Z","finished_at":"2026-07-20T12:05:00Z","web_url":"https://gitlab.acme.test:8443/pipelines/99"}
''';
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok(headPipeline),
        _ok(headPipeline),
        _ok(pipelineDetails),
      ]);
      final provider = GitLabForgeProvider(runner);

      final checks = await provider.getChecks(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
      );
      expect(checks.single.name, 'Pipeline #99');
      expect(checks.single.conclusion, ReviewCheckConclusion.success);
      final details = await provider.getCheckDetails(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
        check: checks.single,
      );
      expect(details!.workflow, 'refs/merge-requests/42/head');
      expect(details.event, 'merge_request_event');
      expect(details.completedAt, DateTime.parse('2026-07-20T12:05:00Z'));
      expect(runner.calls.last.arguments[1], endsWith('/pipelines/99'));
    });

    test('uses only the current head pipeline', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"head_pipeline":{"id":100,"status":"success","web_url":"https://gitlab.acme.test:8443/pipelines/100"}}
'''),
      ]);
      final checks = await GitLabForgeProvider(
        runner,
      ).getChecks(identity: _identity, repoPath: '/repo', number: 42);
      expect(checks, hasLength(1));
      expect(checks.single.name, 'Pipeline #100');
      expect(checks.single.conclusion, ReviewCheckConclusion.success);
      expect(runner.calls.single.arguments[1], endsWith('/merge_requests/42'));
    });

    test('returns null on a 404', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: '404 Not Found',
        ),
      ]);
      final provider = GitLabForgeProvider(runner);
      expect(
        await provider.getReviewByNumber(
          identity: _identity,
          repoPath: '/repo',
          number: 404,
        ),
        isNull,
      );
    });
  });

  group('GitLabForgeProvider comments', () {
    test('maps conversation and resolved inline discussion notes', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"id":"d1","notes":[{"id":1,"system":false,"resolved":true,"body":"Inline","created_at":"2026-07-20T11:00:00Z","author":{"username":"bob"},"position":{"new_path":"lib/a.dart","new_line":17}}]}
{"id":"d2","notes":[{"id":2,"system":false,"body":"General","created_at":"2026-07-20T12:00:00Z","author":{"name":"Carol"}}]}
'''),
      ]);
      final provider = GitLabForgeProvider(runner);

      final comments = await provider.getReviewComments(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
      );
      expect(comments, hasLength(2));
      expect(comments.first.kind, ReviewCommentKind.review);
      expect(comments.first.path, 'lib/a.dart');
      expect(comments.first.line, 17);
      expect(comments.first.resolved, isTrue);
      expect(comments.last.kind, ReviewCommentKind.conversation);
      expect(runner.calls.single.arguments, contains('--paginate'));
    });

    test('maps a single NDJSON discussion record', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"id":"d1","notes":[{"id":1,"system":false,"body":"Only note","created_at":"2026-07-20T11:00:00Z","author":{"username":"bob"}}]}
'''),
      ]);

      final comments = await GitLabForgeProvider(
        runner,
      ).getReviewComments(identity: _identity, repoPath: '/repo', number: 42);

      expect(comments.single.body, 'Only note');
    });

    test('posts a top-level note through the API', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('{}')]);
      final provider = GitLabForgeProvider(runner);
      await provider.addReviewComment(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
        body: 'Ready to merge',
      );
      final call = runner.calls.single;
      expect(call.optionValue('method'), 'POST');
      expect(call.optionValue('raw-field'), 'body=Ready to merge');
      expect(call.arguments[1], endsWith('/merge_requests/42/notes'));
    });

    test(
      'updates top-level and discussion notes through their endpoints',
      () async {
        final topLevelRunner = FakeRecordingProcessRunner(<Object>[_ok('{}')]);
        await GitLabForgeProvider(topLevelRunner).updateReviewComment(
          identity: _identity,
          repoPath: '/repo',
          number: 42,
          locator: const ReviewCommentLocator(
            source: ReviewCommentSource.conversation,
            commentId: '7',
          ),
          body: '- [x] exact',
        );
        expect(
          topLevelRunner.calls.single.arguments[1],
          endsWith('/merge_requests/42/notes/7'),
        );
        expect(topLevelRunner.calls.single.optionValue('method'), 'PUT');
        expect(
          topLevelRunner.calls.single.optionValue('raw-field'),
          'body=- [x] exact',
        );

        final discussionRunner = FakeRecordingProcessRunner(<Object>[
          _ok('{}'),
        ]);
        await GitLabForgeProvider(discussionRunner).updateReviewComment(
          identity: _identity,
          repoPath: '/repo',
          number: 42,
          locator: const ReviewCommentLocator(
            source: ReviewCommentSource.reviewThread,
            commentId: '8',
            parentId: 'discussion-1',
          ),
          body: 'Inline',
        );
        expect(
          discussionRunner.calls.single.arguments[1],
          endsWith('/merge_requests/42/discussions/discussion-1/notes/8'),
        );
        expect(discussionRunner.calls.single.optionValue('method'), 'PUT');
      },
    );
  });

  group('GitLabForgeProvider mutations', () {
    test('creates a draft MR and reads it back', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok(
          'https://gitlab.acme.test/platform/mobile/alera/-/merge_requests/42\n',
        ),
        _ok(_reviewJson),
      ]);
      final provider = GitLabForgeProvider(runner);
      final result = await provider.createReview(
        identity: _identity,
        repoPath: '/repo',
        input: const CreateReviewInput(
          provider: GitHostingProvider.gitlab,
          title: 'feat: gitlab',
          baseBranch: 'main',
          headBranch: 'feature',
          draft: true,
        ),
      );
      expect(result, isA<CreateReviewSuccess>());
      final call = runner.calls.first;
      expect(call.arguments.sublist(0, 2), <String>['mr', 'create']);
      expect(call.optionValue('repo'), _repoUrl);
      expect(call.arguments, containsAll(<String>['--draft', '--yes']));
      expect(runner.calls.last.arguments[1], endsWith('/merge_requests/42'));
    });

    test('updates title and target branch then reads back', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok(''),
        _ok(_reviewJson),
      ]);
      final provider = GitLabForgeProvider(runner);
      final result = await provider.updateReview(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
        input: const UpdateReviewInput(
          title: 'feat: renamed',
          baseBranch: 'develop',
        ),
      );
      expect(result, isA<UpdateReviewSuccess>());
      expect(runner.calls.first.optionValue('title'), 'feat: renamed');
      expect(runner.calls.first.optionValue('target-branch'), 'develop');
    });

    for (final entry in <(ReviewMergeMethod, String?)>[
      (ReviewMergeMethod.providerDefault, null),
      (ReviewMergeMethod.squash, '--squash'),
    ]) {
      test('merges with ${entry.$1.name}', () async {
        final runner = FakeRecordingProcessRunner(<Object>[_ok('')]);
        final provider = GitLabForgeProvider(runner);
        await provider.mergeReview(
          identity: _identity,
          repoPath: '/repo',
          number: 42,
          method: entry.$1,
        );
        final arguments = runner.calls.single.arguments;
        expect(arguments.sublist(0, 3), <String>['mr', 'merge', '42']);
        expect(arguments, contains('--auto-merge=false'));
        if (entry.$2 != null) expect(arguments, contains(entry.$2));
      });
    }

    test('rejects GitHub-style rebase-and-merge semantics', () async {
      final provider = GitLabForgeProvider(
        FakeRecordingProcessRunner(<Object>[]),
      );
      expect(
        () => provider.mergeReview(
          identity: _identity,
          repoPath: '/repo',
          number: 42,
          method: ReviewMergeMethod.rebase,
        ),
        throwsA(isA<ForgeRequestFailed>()),
      );
    });

    test('closes and marks an MR ready through glab', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok(''), _ok('')]);
      final provider = GitLabForgeProvider(runner);
      await provider.closeReview(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
      );
      await provider.setReviewDraft(
        identity: _identity,
        repoPath: '/repo',
        number: 42,
        draft: false,
      );
      expect(runner.calls.first.arguments.sublist(0, 3), <String>[
        'mr',
        'close',
        '42',
      ]);
      expect(runner.calls.last.arguments, contains('--ready'));
    });
  });

  group('GitLabForgeProvider auth', () {
    test('checks the remote host', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('')]);
      final provider = GitLabForgeProvider(runner);
      expect(
        await provider.checkAuth(identity: _identity),
        ForgeAuthStatus.authenticated,
      );
      expect(
        runner.calls.single.optionValue('hostname'),
        'gitlab.acme.test:8443',
      );
    });

    test('reports a missing CLI', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        ProcessException('glab', const <String>[]),
      ]);
      final provider = GitLabForgeProvider(runner);
      expect(
        await provider.checkAuth(identity: _identity),
        ForgeAuthStatus.cliMissing,
      );
    });
  });
}

const _repoUrl = 'https://gitlab.acme.test:8443/platform/mobile/alera';
