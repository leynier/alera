import 'package:alera/src/shared/git_hosting/application/git_remote_parser.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseGitRemoteIdentity - GitHub', () {
    test('parses HTTPS with .git suffix', () {
      final id = parseGitRemoteIdentity('https://github.com/leynier/alera.git');
      expect(id, isNotNull);
      expect(id!.provider, GitHostingProvider.github);
      expect(id.host, 'github.com');
      expect(id.owner, 'leynier');
      expect(id.repo, 'alera');
      expect(id.project, isNull);
    });

    test('parses HTTPS without .git suffix', () {
      final id = parseGitRemoteIdentity('https://github.com/leynier/alera');
      expect(id!.owner, 'leynier');
      expect(id.repo, 'alera');
    });

    test('parses scp-like SSH', () {
      final id = parseGitRemoteIdentity('git@github.com:leynier/alera.git');
      expect(id!.provider, GitHostingProvider.github);
      expect(id.owner, 'leynier');
      expect(id.repo, 'alera');
    });

    test('parses ssh:// URL form', () {
      final id = parseGitRemoteIdentity(
        'ssh://git@github.com/leynier/alera.git',
      );
      expect(id!.owner, 'leynier');
      expect(id.repo, 'alera');
    });
  });

  group('parseGitRemoteIdentity - Azure DevOps', () {
    test('parses dev.azure.com HTTPS', () {
      final id = parseGitRemoteIdentity(
        'https://dev.azure.com/myorg/myproject/_git/myrepo',
      );
      expect(id!.provider, GitHostingProvider.azureDevops);
      expect(id.owner, 'myorg');
      expect(id.project, 'myproject');
      expect(id.repo, 'myrepo');
    });

    test('parses dev.azure.com HTTPS with org userinfo prefix', () {
      final id = parseGitRemoteIdentity(
        'https://myorg@dev.azure.com/myorg/myproject/_git/myrepo',
      );
      expect(id!.owner, 'myorg');
      expect(id.project, 'myproject');
      expect(id.repo, 'myrepo');
    });

    test('parses ssh.dev.azure.com SSH v3 form', () {
      final id = parseGitRemoteIdentity(
        'git@ssh.dev.azure.com:v3/myorg/myproject/myrepo',
      );
      expect(id!.provider, GitHostingProvider.azureDevops);
      expect(id.owner, 'myorg');
      expect(id.project, 'myproject');
      expect(id.repo, 'myrepo');
    });

    test('parses legacy visualstudio.com HTTPS', () {
      final id = parseGitRemoteIdentity(
        'https://myorg.visualstudio.com/myproject/_git/myrepo',
      );
      expect(id!.provider, GitHostingProvider.azureDevops);
      expect(id.owner, 'myorg');
      expect(id.project, 'myproject');
      expect(id.repo, 'myrepo');
    });

    test('parses legacy vs-ssh.visualstudio.com SSH', () {
      final id = parseGitRemoteIdentity(
        'git@vs-ssh.visualstudio.com:v3/myorg/myproject/myrepo',
      );
      expect(id!.owner, 'myorg');
      expect(id.project, 'myproject');
      expect(id.repo, 'myrepo');
    });
  });

  group('parseGitRemoteIdentity - GitLab', () {
    test('parses HTTPS with nested groups', () {
      final id = parseGitRemoteIdentity(
        'https://gitlab.com/platform/mobile/alera.git',
      );
      expect(id, isNotNull);
      expect(id!.provider, GitHostingProvider.gitlab);
      expect(id.host, 'gitlab.com');
      expect(id.owner, 'platform/mobile');
      expect(id.repo, 'alera');
    });

    test('parses scp-like SSH', () {
      final id = parseGitRemoteIdentity('git@gitlab.com:team/alera.git');
      expect(id!.provider, GitHostingProvider.gitlab);
      expect(id.owner, 'team');
      expect(id.repo, 'alera');
    });
  });

  group('parseGitRemoteIdentity - unsupported / malformed', () {
    test('returns null for an unknown host', () {
      expect(parseGitRemoteIdentity('https://codeberg.org/o/r.git'), isNull);
    });

    test('returns null for empty input', () {
      expect(parseGitRemoteIdentity('   '), isNull);
    });

    test('returns null for a github URL missing the repo', () {
      expect(parseGitRemoteIdentity('https://github.com/leynier'), isNull);
    });
  });

  group('parseRemoteAsProvider - override forces interpretation', () {
    test('forces GitHub on a self-hosted enterprise host', () {
      final id = parseRemoteAsProvider(
        'https://github.mycorp.com/team/service.git',
        .github,
      );
      expect(id, isNotNull);
      expect(id!.provider, GitHostingProvider.github);
      expect(id.host, 'github.mycorp.com');
      expect(id.owner, 'team');
      expect(id.repo, 'service');
    });

    test('forces Azure on a dev.azure.com remote', () {
      final id = parseRemoteAsProvider(
        'https://dev.azure.com/myorg/myproject/_git/myrepo',
        .azureDevops,
      );
      expect(id!.provider, GitHostingProvider.azureDevops);
      expect(id.owner, 'myorg');
      expect(id.project, 'myproject');
    });

    test('forces GitLab on a self-hosted instance with nested groups', () {
      final id = parseRemoteAsProvider(
        'git@gitlab.acme.test:platform/mobile/app.git',
        .gitlab,
      );
      expect(id!.provider, GitHostingProvider.gitlab);
      expect(id.host, 'gitlab.acme.test');
      expect(id.owner, 'platform/mobile');
      expect(id.repo, 'app');
    });

    test('preserves the HTTPS port for a self-hosted GitLab instance', () {
      final id = parseRemoteAsProvider(
        'https://gitlab.acme.test:8443/platform/mobile/app.git',
        .gitlab,
      );
      expect(id!.host, 'gitlab.acme.test:8443');
      expect(id.owner, 'platform/mobile');
    });

    test('does not use an SSH transport port as the GitLab API port', () {
      final id = parseRemoteAsProvider(
        'ssh://git@gitlab.acme.test:2222/platform/mobile/app.git',
        .gitlab,
      );
      expect(id!.host, 'gitlab.acme.test');
      expect(id.owner, 'platform/mobile');
    });

    test('returns null when the shape cannot satisfy the forced provider', () {
      // A plain owner/repo remote cannot yield an Azure project.
      final id = parseRemoteAsProvider(
        'git@example.com:owner/repo.git',
        .azureDevops,
      );
      expect(id, isNull);
    });
  });
}
