import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/infra/azure_devops_forge_provider.dart';
import 'package:alera/src/features/pull_requests/infra/github_forge_provider.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_process_runner.dart';

const _githubIdentity = GitRemoteIdentity(
  provider: .github,
  host: 'github.com',
  owner: 'leynier',
  repo: 'alera',
);

const _azureIdentity = GitRemoteIdentity(
  provider: .azureDevops,
  host: 'dev.azure.com',
  owner: 'myorg',
  repo: 'myrepo',
  project: 'myproject',
);

ProcessRunOutput _ok(String stdout) =>
    ProcessRunOutput(exitCode: 0, stdout: stdout, stderr: '');

void main() {
  group('GitHubForgeProvider comments', () {
    test('routes Enterprise API requests to the remote host', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('[[]]'),
        _ok(
          '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}',
        ),
        _ok('[[]]'),
      ]);
      final provider = GitHubForgeProvider(runner);

      await provider.getReviewComments(
        identity: const GitRemoteIdentity(
          provider: .github,
          host: 'github.mycorp.com',
          owner: 'team',
          repo: 'svc',
        ),
        repoPath: '/repo',
        number: 123,
      );

      for (final call in runner.calls) {
        expect(call.optionValue('hostname'), 'github.mycorp.com');
      }
    });

    test('paginates review threads and every thread comment', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('[[]]'),
        _ok('''
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":true,"endCursor":"THREADS-1"},"nodes":[{"id":"T1","isResolved":false,"line":7,"comments":{"pageInfo":{"hasNextPage":true,"endCursor":"COMMENTS-1"},"nodes":[{"databaseId":1,"author":{"login":"alice"},"body":"First","createdAt":"2026-07-16T10:00:00Z","path":"lib/a.dart"}]}}]}}}}}
'''),
        _ok('[[]]'),
        _ok('''
{"data":{"node":{"comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"databaseId":2,"author":{"login":"bob"},"body":"Reply","createdAt":"2026-07-16T11:00:00Z","path":"lib/a.dart"}]}}}}
'''),
        _ok('''
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"T2","isResolved":true,"originalLine":9,"comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"databaseId":3,"author":{"login":"carol"},"body":"Second thread","createdAt":"2026-07-16T12:00:00Z","path":"lib/b.dart"}]}}]}}}}}
'''),
      ]);

      final comments = await GitHubForgeProvider(runner).getReviewComments(
        identity: _githubIdentity,
        repoPath: '/repo',
        number: 123,
      );

      expect(comments.map((comment) => comment.body), <String>[
        'First',
        'Reply',
        'Second thread',
      ]);
      expect(runner.calls[3].arguments, contains('thread=T1'));
      expect(runner.calls[3].arguments, contains('commentsAfter=COMMENTS-1'));
      expect(runner.calls[4].arguments, contains('threadsAfter=THREADS-1'));
    });

    test('loads conversation, reviews, and resolved inline threads', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
[[{"id":1,"user":{"login":"alice"},"body":"General note","created_at":"2026-07-16T12:00:00Z","html_url":"https://github.com/leynier/alera/pull/123#issuecomment-1"}]]
'''),
        _ok('''
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"T1","isResolved":true,"line":null,"originalLine":17,"comments":{"nodes":[{"databaseId":2,"author":{"login":"bob"},"body":"Change this line","createdAt":"2026-07-16T11:00:00Z","url":"https://github.com/leynier/alera/pull/123#discussion_r2","path":"lib/a.dart"}]}}]}}}}}
'''),
        _ok('''
[[{"id":3,"user":{"login":"carol"},"body":"LGTM","state":"APPROVED","submitted_at":"2026-07-16T13:00:00Z","html_url":"https://github.com/leynier/alera/pull/123#pullrequestreview-3"}]]
'''),
      ]);
      final provider = GitHubForgeProvider(runner);

      final comments = await provider.getReviewComments(
        identity: _githubIdentity,
        repoPath: '/repo',
        number: 123,
      );

      expect(comments, hasLength(3));
      expect(comments.first.author, 'bob');
      expect(comments.first.kind, ReviewCommentKind.review);
      expect(comments.first.path, 'lib/a.dart');
      expect(comments.first.line, 17);
      expect(comments.first.resolved, isTrue);
      expect(comments[1].body, 'General note');
      expect(comments.last.body, 'LGTM');
      expect(
        runner.calls.first.arguments,
        contains('repos/leynier/alera/issues/123/comments?per_page=100'),
      );
      expect(runner.calls[1].arguments, contains('graphql'));
      expect(
        runner.calls.last.arguments,
        contains('repos/leynier/alera/pulls/123/reviews?per_page=100'),
      );
      expect(
        runner.calls.first.arguments,
        containsAll(<String>['--paginate', '--slurp']),
      );
    });

    test('keeps available sources when GraphQL threads fail', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
[[{"id":1,"user":{"login":"alice"},"body":"General note","created_at":"2026-07-16T12:00:00Z","html_url":"https://github.com/leynier/alera/pull/123#issuecomment-1"}]]
'''),
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'GraphQL temporarily unavailable',
        ),
        _ok('[[]]'),
      ]);
      final provider = GitHubForgeProvider(runner);

      final comments = await provider.getReviewComments(
        identity: _githubIdentity,
        repoPath: '/repo',
        number: 123,
      );

      expect(comments.single.body, 'General note');
    });

    test('keeps the first thread page when the next page fails', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('[[]]'),
        _ok('''
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":true,"endCursor":"THREADS-1"},"nodes":[{"id":"T1","isResolved":false,"line":7,"comments":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"databaseId":1,"author":{"login":"alice"},"body":"First page","createdAt":"2026-07-16T10:00:00Z","path":"lib/a.dart"}]}}]}}}}}
'''),
        _ok('[[]]'),
        const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'GraphQL page unavailable',
        ),
      ]);

      final comments = await GitHubForgeProvider(runner).getReviewComments(
        identity: _githubIdentity,
        repoPath: '/repo',
        number: 123,
      );

      expect(comments.single.body, 'First page');
      expect(runner.calls.last.arguments, contains('threadsAfter=THREADS-1'));
    });

    test(
      'keeps initial thread comments when reply continuation fails',
      () async {
        final runner = FakeRecordingProcessRunner(<Object>[
          _ok('[[]]'),
          _ok('''
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"T1","isResolved":false,"line":7,"comments":{"pageInfo":{"hasNextPage":true,"endCursor":"COMMENTS-1"},"nodes":[{"databaseId":1,"author":{"login":"alice"},"body":"First reply page","createdAt":"2026-07-16T10:00:00Z","path":"lib/a.dart"}]}}]}}}}}
'''),
          _ok('[[]]'),
          const ProcessRunOutput(
            exitCode: 1,
            stdout: '',
            stderr: 'GraphQL replies unavailable',
          ),
        ]);

        final comments = await GitHubForgeProvider(runner).getReviewComments(
          identity: _githubIdentity,
          repoPath: '/repo',
          number: 123,
        );

        expect(comments.single.body, 'First reply page');
        expect(
          runner.calls.last.arguments,
          contains('commentsAfter=COMMENTS-1'),
        );
      },
    );

    test('posts a top-level comment through gh pr comment', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('')]);
      final provider = GitHubForgeProvider(runner);

      await provider.addReviewComment(
        identity: _githubIdentity,
        repoPath: '/repo',
        number: 123,
        body: 'Ready to merge',
      );

      final call = runner.calls.single;
      expect(call.arguments.sublist(0, 3), <String>['pr', 'comment', '123']);
      expect(call.optionValue('repo'), 'leynier/alera');
      expect(call.optionValue('body'), 'Ready to merge');
    });

    test('updates conversation, review summary, and inline comments', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('{}'),
        _ok('{}'),
        _ok('{}'),
      ]);
      final provider = GitHubForgeProvider(runner);

      await provider.updateReviewComment(
        identity: _githubIdentity,
        repoPath: '/repo',
        number: 123,
        locator: const ReviewCommentLocator(
          source: .conversation,
          commentId: '11',
        ),
        body: '- [x] exact\nline',
      );
      await provider.updateReviewComment(
        identity: _githubIdentity,
        repoPath: '/repo',
        number: 123,
        locator: const ReviewCommentLocator(
          source: .reviewSummary,
          commentId: '12',
        ),
        body: 'Summary',
      );
      await provider.updateReviewComment(
        identity: _githubIdentity,
        repoPath: '/repo',
        number: 123,
        locator: const ReviewCommentLocator(
          source: .reviewThread,
          commentId: '13',
          parentId: 'thread-1',
        ),
        body: 'Inline',
      );

      expect(
        runner.calls[0].arguments,
        contains('repos/leynier/alera/issues/comments/11'),
      );
      expect(runner.calls[0].optionValue('method'), 'PATCH');
      expect(
        runner.calls[0].optionValue('raw-field'),
        'body=- [x] exact\nline',
      );
      expect(
        runner.calls[1].arguments,
        contains('repos/leynier/alera/pulls/123/reviews/12'),
      );
      expect(
        runner.calls[2].arguments,
        contains('repos/leynier/alera/pulls/comments/13'),
      );
    });
  });

  group('AzureDevOpsForgeProvider comments', () {
    test('maps conversation and inline thread comments', () async {
      final runner = FakeRecordingProcessRunner(<Object>[
        _ok('''
{"count":2,"value":[
  {"id":10,"status":"active","comments":[{"id":1,"author":{"displayName":"Alice"},"content":"General note","publishedDate":"2026-07-16T12:00:00Z","commentType":"text"}]},
  {"id":11,"status":"fixed","threadContext":{"filePath":"/lib/a.dart","rightFileStart":{"line":9,"offset":1}},"comments":[{"id":1,"author":{"displayName":"Bob"},"content":"Change this","publishedDate":"2026-07-16T11:00:00Z","commentType":"text"},{"id":2,"content":"system","publishedDate":"2026-07-16T11:01:00Z","commentType":"system"}]}
]}
'''),
      ]);
      final provider = AzureDevOpsForgeProvider(runner);

      final comments = await provider.getReviewComments(
        identity: _azureIdentity,
        repoPath: '/repo',
        number: 42,
      );

      expect(comments, hasLength(2));
      expect(comments.first.author, 'Bob');
      expect(comments.first.kind, ReviewCommentKind.review);
      expect(comments.first.path, '/lib/a.dart');
      expect(comments.first.line, 9);
      expect(comments.first.resolved, isTrue);
      expect(comments.last.kind, ReviewCommentKind.conversation);
      final call = runner.calls.single;
      expect(call.optionValue('resource'), 'pullRequestThreads');
      expect(call.optionValue('http-method'), 'GET');
      expect(call.arguments, contains('pullRequestId=42'));
    });

    test('creates a top-level comment thread', () async {
      final runner = FakeRecordingProcessRunner(<Object>[_ok('{}')]);
      final provider = AzureDevOpsForgeProvider(runner);

      await provider.addReviewComment(
        identity: _azureIdentity,
        repoPath: '/repo',
        number: 42,
        body: 'Ready to merge',
      );

      final call = runner.calls.single;
      expect(call.optionValue('resource'), 'pullRequestThreads');
      expect(call.optionValue('http-method'), 'POST');
      expect(call.optionValue('api-version'), '7.1');
      expect(call.optionValue('in-file'), isNotNull);
      expect(call.arguments, contains('project=myproject'));
      expect(call.arguments, contains('repositoryId=myrepo'));
      expect(call.arguments, contains('pullRequestId=42'));
    });

    test('builds the documented top-level thread body', () {
      expect(
        AzureDevOpsForgeProvider.commentThreadBodyJson('Ready'),
        '{"comments":[{"parentCommentId":0,"content":"Ready",'
        '"commentType":1}],"status":1}',
      );
    });

    test(
      'updates a thread comment through the official comment endpoint',
      () async {
        final runner = FakeRecordingProcessRunner(<Object>[_ok('{}')]);
        final provider = AzureDevOpsForgeProvider(runner);

        await provider.updateReviewComment(
          identity: _azureIdentity,
          repoPath: '/repo',
          number: 42,
          locator: const ReviewCommentLocator(
            source: .reviewThread,
            commentId: '2',
            parentId: '11',
          ),
          body: '- [x] exact',
        );

        final call = runner.calls.single;
        expect(call.optionValue('resource'), 'pullRequestThreadComments');
        expect(call.optionValue('http-method'), 'PATCH');
        expect(call.arguments, contains('threadId=11'));
        expect(call.arguments, contains('commentId=2'));
        expect(
          AzureDevOpsForgeProvider.commentBodyJson('- [x] exact'),
          '{"content":"- [x] exact"}',
        );
      },
    );
  });
}
