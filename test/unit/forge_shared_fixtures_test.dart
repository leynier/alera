import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/infra/azure_devops_forge_provider.dart';
import 'package:alera/src/features/pull_requests/infra/gitlab_forge_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_process_runner.dart';

/// The recorded `glab` and `az` output in `test/fixtures/forges/`, which the
/// runtime's Rust providers read too (`pull_request_forges/fixture_tests.rs`).
/// Both ports must map it to the same neutral expectation.
Map<String, Object?> _fixture(String name) =>
    jsonDecode(File('test/fixtures/forges/$name').readAsStringSync())
        as Map<String, Object?>;

FakeRecordingProcessRunner _runner(Map<String, Object?> fixture) =>
    FakeRecordingProcessRunner(<Object>[
      ProcessRunOutput(
        exitCode: 0,
        stdout: fixture['stdout']! as String,
        stderr: '',
      ),
    ]);

const _gitlab = GitRemoteIdentity(
  provider: .gitlab,
  host: 'gitlab.acme.test:8443',
  owner: 'platform/mobile',
  repo: 'alera',
);

GitRemoteIdentity _azure(Map<String, Object?> fixture) {
  final identity = fixture['identity']! as Map<String, Object?>;
  return GitRemoteIdentity(
    provider: .azureDevops,
    host: identity['host']! as String,
    owner: identity['owner']! as String,
    repo: identity['repo']! as String,
    project: identity['project'] as String?,
  );
}

Map<String, Object?> _expected(Map<String, Object?> fixture) =>
    fixture['expected']! as Map<String, Object?>;

void _expectReview(HostedReview? review, Object? expected) {
  final values = expected! as Map<String, Object?>;
  expect(review, isNotNull);
  expect(review!.number, values['number']);
  expect(review.title, values['title']);
  expect(review.state.name, values['state']);
  expect(review.author, values['author']);
  expect(review.baseBranch, values['baseBranch']);
  expect(review.headBranch, values['headBranch']);
  expect(review.headSha, values['headSha']);
  expect(review.mergeable.name, values['mergeable']);
  expect(review.url, values['url']);
}

void _expectChecks(
  List<ReviewCheck> checks,
  Object? expected, {
  bool compareUrl = true,
}) {
  final values = (expected! as List<Object?>).cast<Map<String, Object?>>();
  expect(checks, hasLength(values.length));
  for (final (index, check) in checks.indexed) {
    expect(check.name, values[index]['name']);
    expect(check.conclusion.name, values[index]['conclusion']);
    if (compareUrl) {
      expect(check.url, values[index]['url']);
    }
  }
}

void _expectComments(List<ReviewComment> comments, Object? expected) {
  final values = (expected! as List<Object?>).cast<Map<String, Object?>>();
  expect(comments, hasLength(values.length));
  for (final (index, comment) in comments.indexed) {
    final value = values[index];
    expect(comment.author, value['author']);
    expect(comment.body, value['body']);
    expect(comment.kind.name, value['kind']);
    expect(comment.path, value['path']);
    expect(comment.line, value['line']);
    expect(comment.resolved, value['resolved']);
    expect(comment.threadId, value['threadId']);
  }
}

void main() {
  group('shared GitLab fixtures', () {
    for (final name in <String>[
      'gitlab_merge_request.json',
      'gitlab_draft_conflicting_merge_request.json',
    ]) {
      test('$name maps the merge request and its pipeline', () async {
        final fixture = _fixture(name);
        final expected = _expected(fixture);
        final number =
            (expected['review']! as Map<String, Object?>)['number']! as int;
        _expectReview(
          await GitLabForgeProvider(_runner(fixture)).getReviewByNumber(
            identity: _gitlab,
            repoPath: '/repo',
            number: number,
          ),
          expected['review'],
        );
        _expectChecks(
          await GitLabForgeProvider(_runner(fixture))
              .getChecks(identity: _gitlab, repoPath: '/repo', number: number),
          expected['checks'],
        );
      });
    }

    test('gitlab_discussions.json maps notes and threads', () async {
      final fixture = _fixture('gitlab_discussions.json');
      _expectComments(
        await GitLabForgeProvider(
          _runner(fixture),
        ).getReviewComments(identity: _gitlab, repoPath: '/repo', number: 42),
        _expected(fixture)['comments'],
      );
    });
  });

  group('shared Azure DevOps fixtures', () {
    test('azure_pull_requests.json picks and maps the newest', () async {
      final fixture = _fixture('azure_pull_requests.json');
      _expectReview(
        await AzureDevOpsForgeProvider(_runner(fixture)).getReviewForBranch(
          identity: _azure(fixture),
          repoPath: '/repo',
          branch: 'feature',
        ),
        _expected(fixture)['review'],
      );
    });

    test('azure_completed_pull_request.json maps a merged review', () async {
      final fixture = _fixture('azure_completed_pull_request.json');
      _expectReview(
        await AzureDevOpsForgeProvider(_runner(fixture)).getReviewByNumber(
          identity: _azure(fixture),
          repoPath: '/repo',
          number: 9,
        ),
        _expected(fixture)['review'],
      );
    });

    test('azure_policies.json maps policy evaluations', () async {
      final fixture = _fixture('azure_policies.json');
      // The desktop keeps the build link in the check details, not the check.
      _expectChecks(
        await AzureDevOpsForgeProvider(
          _runner(fixture),
        ).getChecks(identity: _azure(fixture), repoPath: '/repo', number: 42),
        _expected(fixture)['checks'],
        compareUrl: false,
      );
    });

    test('azure_threads.json maps live thread comments', () async {
      final fixture = _fixture('azure_threads.json');
      _expectComments(
        await AzureDevOpsForgeProvider(_runner(fixture)).getReviewComments(
          identity: _azure(fixture),
          repoPath: '/repo',
          number: 42,
        ),
        _expected(fixture)['comments'],
      );
    });
  });
}
