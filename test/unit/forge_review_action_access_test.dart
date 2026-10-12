import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/infra/github_forge_provider.dart';
import 'package:alera/src/features/pull_requests/infra/gitlab_forge_provider.dart';
import 'package:alera/src/features/pull_requests/infra/azure_devops_forge_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recording_process_runner.dart';

const review = HostedReview(
  provider: .github,
  number: 123,
  title: 'Details',
  state: .open,
  url: '',
  baseBranch: 'main',
);
ProcessRunOutput ok(String json) =>
    ProcessRunOutput(exitCode: 0, stdout: json, stderr: '');
void main() {
  const github = GitRemoteIdentity(
    provider: .github,
    host: 'github.com',
    owner: 'org',
    repo: 'repo',
  );
  test('GitHub combines account write access and PR merge state', () async {
    for (final permitted in [true, false]) {
      final runner = FakeRecordingProcessRunner([
        ok('{"permissions":{"push":$permitted}}'),
        ok('{"mergeable_state":"clean"}'),
      ]);
      final access = await GitHubForgeProvider(runner).reviewActionAccess(
        identity: github,
        repoPath: '/checkout',
        review: review,
      );
      expect(access.canMerge, permitted);
      expect(access.canMarkReady, permitted);
      expect(runner.calls.last.arguments, contains('repos/org/repo/pulls/123'));
    }
  });
  test('GitHub unknown or blocked merge state does not permit merge', () async {
    for (final output in ['{}', '{"mergeable_state":"blocked"}']) {
      final access =
          await GitHubForgeProvider(
            FakeRecordingProcessRunner([
              ok('{"permissions":{"push":true}}'),
              ok(output),
            ]),
          ).reviewActionAccess(
            identity: github,
            repoPath: '/checkout',
            review: review,
          );
      expect(access.canMerge, isNot(true));
      expect(access.canMarkReady, isTrue);
    }
  });
  test(
    'GitLab uses documented MR merge permission and inherited developer role',
    () async {
      final runner = FakeRecordingProcessRunner([
        ok('{"user":{"can_merge":false}}'),
        ok('{"permissions":{"group_access":{"access_level":30}}}'),
      ]);
      final access = await GitLabForgeProvider(runner).reviewActionAccess(
        identity: const GitRemoteIdentity(
          provider: .gitlab,
          host: 'gitlab.com',
          owner: 'org',
          repo: 'repo',
        ),
        repoPath: '/checkout',
        review: review.copyWith(provider: .gitlab),
      );
      expect(access.canMerge, isFalse);
      expect(access.canMarkReady, isTrue);
    },
  );
  test(
    'Azure checks effective branch and PR permissions using namespace bits',
    () async {
      final runner = FakeRecordingProcessRunner([
        ok('{"id":"repo-id","project":{"id":"project-id"}}'),
        ok(
          '[{"actions":[{"name":"GenericContribute","bit":4},{"name":"PullRequestContribute","bit":16384}]}]',
        ),
        ok('[true]'),
        ok('[false]'),
      ]);
      final access = await AzureDevOpsForgeProvider(runner).reviewActionAccess(
        identity: const GitRemoteIdentity(
          provider: .azureDevops,
          host: 'dev.azure.com',
          owner: 'org',
          project: 'project',
          repo: 'repo',
        ),
        repoPath: '/checkout',
        review: review.copyWith(provider: .azureDevops),
      );
      expect(access.canMerge, isFalse);
      expect(access.canMarkReady, isFalse);
      expect(
        runner.calls[2].arguments,
        contains(
          'tokens=repoV2/project-id/repo-id/refs/heads/6d00610069006e00/',
        ),
      );
      expect(runner.calls[3].arguments, contains('permissions=16384'));
    },
  );
}
