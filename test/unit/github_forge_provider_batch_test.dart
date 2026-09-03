import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/infra/github_forge_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_process_runner.dart';

const _identity = GitRemoteIdentity(
  provider: .github,
  host: 'github.com',
  owner: 'leynier',
  repo: 'alera',
);

ProcessRunOutput _ok(String stdout) =>
    ProcessRunOutput(exitCode: 0, stdout: stdout, stderr: '');

void main() {
  test('loads branches and linked PRs in one GraphQL process', () async {
    final runner = FakeRecordingProcessRunner(<Object>[
      _ok('''
{"data":{"repository":{
  "branch0":{"nodes":[{"number":123,"title":"feat: sidebar status","state":"OPEN","url":"https://github.com/leynier/alera/pull/123","createdAt":"2026-09-01T00:00:00Z","isDraft":false,"mergeable":"MERGEABLE","headRefName":"feature","baseRefName":"main","headRefOid":"abc","commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[{"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":null,"detailsUrl":"https://ci/build"},{"__typename":"StatusContext","context":"lint","state":"FAILURE","targetUrl":"https://ci/lint"}]}}}}]}}]},
  "review0":{"number":77,"title":"merged work","state":"MERGED","url":"https://github.com/leynier/alera/pull/77","createdAt":"2026-08-01T00:00:00Z","isDraft":false,"mergeable":"UNKNOWN","headRefName":"old-feature","baseRefName":"main","headRefOid":"def","commits":{"nodes":[]}}
}}}
'''),
    ]);
    final provider = GitHubForgeProvider(runner);

    final batch = await provider.getReviewBatch(
      identity: _identity,
      repoPath: '/repo',
      branches: const <String>{'feature'},
      reviewNumbers: const <int>{77},
    );

    final call = runner.calls.single;
    expect(call.executable, 'gh');
    expect(call.arguments.take(2), <String>['api', 'graphql']);
    expect(call.workingDirectory, '/repo');
    expect(call.arguments, contains('branch0=feature'));
    expect(call.arguments, contains('number0=77'));
    expect(
      call.arguments.firstWhere((argument) => argument.startsWith('query=')),
      contains('statusCheckRollup'),
    );

    final feature = batch.byBranch['feature'];
    expect(feature, isNotNull);
    expect(feature!.review.number, 123);
    expect(feature.checks, hasLength(2));
    expect(feature.checks[0].status, ReviewCheckStatus.inProgress);
    expect(feature.checks[0].conclusion, ReviewCheckConclusion.pending);
    expect(feature.checks[1].conclusion, ReviewCheckConclusion.failure);
    expect(batch.byNumber[123], same(feature));
    expect(batch.byNumber[77]!.review.state, HostedReviewState.merged);
    expect(batch.byBranch['old-feature']!.review.number, 77);
  });
}
