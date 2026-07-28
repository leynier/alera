import 'package:alera/src/shared/git_hosting/application/repository_web_url.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('azureOrgUrl', () {
    test('modern dev.azure.com host', () {
      final identity = GitRemoteIdentity(
        provider: GitHostingProvider.azureDevops,
        host: 'dev.azure.com',
        owner: 'contoso',
        repo: 'app',
        project: 'App',
      );
      expect(azureOrgUrl(identity), 'https://dev.azure.com/contoso');
    });

    test('ssh.dev.azure.com maps to dev.azure.com org url', () {
      final identity = GitRemoteIdentity(
        provider: GitHostingProvider.azureDevops,
        host: 'ssh.dev.azure.com',
        owner: 'contoso',
        repo: 'app',
        project: 'App',
      );
      expect(azureOrgUrl(identity), 'https://dev.azure.com/contoso');
    });

    test('legacy visualstudio.com host embeds org in subdomain', () {
      final identity = GitRemoteIdentity(
        provider: GitHostingProvider.azureDevops,
        host: 'contoso.visualstudio.com',
        owner: 'contoso',
        repo: 'app',
        project: 'App',
      );
      expect(azureOrgUrl(identity), 'https://contoso.visualstudio.com');
    });
  });

  group('repositoryWebUrl', () {
    test('github.com', () {
      final identity = GitRemoteIdentity(
        provider: GitHostingProvider.github,
        host: 'github.com',
        owner: 'leynier',
        repo: 'alera',
      );
      expect(repositoryWebUrl(identity), 'https://github.com/leynier/alera');
    });

    test('github enterprise host with HTTPS port', () {
      final identity = GitRemoteIdentity(
        provider: GitHostingProvider.github,
        host: 'git.acme.inc:8443',
        owner: 'team',
        repo: 'service',
      );
      expect(
        repositoryWebUrl(identity),
        'https://git.acme.inc:8443/team/service',
      );
    });

    test('gitlab self-hosted with nested groups', () {
      final identity = GitRemoteIdentity(
        provider: GitHostingProvider.gitlab,
        host: 'gitlab.acme.inc',
        owner: 'platform/mobile',
        repo: 'service',
      );
      expect(
        repositoryWebUrl(identity),
        'https://gitlab.acme.inc/platform/mobile/service',
      );
    });

    test('azure devops dev.azure.com', () {
      final identity = GitRemoteIdentity(
        provider: GitHostingProvider.azureDevops,
        host: 'dev.azure.com',
        owner: 'contoso',
        repo: 'app',
        project: 'App',
      );
      expect(
        repositoryWebUrl(identity),
        'https://dev.azure.com/contoso/App/_git/app',
      );
    });

    test('azure devops visualstudio.com legacy', () {
      final identity = GitRemoteIdentity(
        provider: GitHostingProvider.azureDevops,
        host: 'contoso.visualstudio.com',
        owner: 'contoso',
        repo: 'app',
        project: 'App',
      );
      expect(
        repositoryWebUrl(identity),
        'https://contoso.visualstudio.com/App/_git/app',
      );
    });

    test('azure devops falls back to repo name when project missing', () {
      final identity = GitRemoteIdentity(
        provider: GitHostingProvider.azureDevops,
        host: 'dev.azure.com',
        owner: 'contoso',
        repo: 'solo',
        project: null,
      );
      expect(
        repositoryWebUrl(identity),
        'https://dev.azure.com/contoso/solo/_git/solo',
      );
    });
  });
}
