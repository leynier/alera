import 'package:alera/src/shared/git_hosting/application/hosting_provider_resolver.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/infra/git/git_remote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveHostingProvider', () {
    test('auto-detects GitHub from the origin remote', () {
      final result = resolveHostingProvider(
        remotes: const <GitRemote>[
          GitRemote(
            name: 'origin',
            url: 'https://github.com/leynier/alera.git',
          ),
        ],
      );
      expect(result, isA<HostingProviderResolved>());
      final resolved = result as HostingProviderResolved;
      expect(resolved.fromOverride, isFalse);
      expect(resolved.identity.provider, GitHostingProvider.github);
      expect(resolved.identity.owner, 'leynier');
    });

    test('prefers origin over other remotes', () {
      final result = resolveHostingProvider(
        remotes: const <GitRemote>[
          GitRemote(name: 'fork', url: 'https://github.com/other/alera.git'),
          GitRemote(
            name: 'origin',
            url: 'https://github.com/leynier/alera.git',
          ),
        ],
      );
      final resolved = result as HostingProviderResolved;
      expect(resolved.identity.owner, 'leynier');
    });

    test('falls back to upstream when there is no origin', () {
      final result = resolveHostingProvider(
        remotes: const <GitRemote>[
          GitRemote(name: 'upstream', url: 'https://github.com/up/alera.git'),
          GitRemote(name: 'other', url: 'https://github.com/x/alera.git'),
        ],
      );
      final resolved = result as HostingProviderResolved;
      expect(resolved.identity.owner, 'up');
    });

    test('override forces the provider and marks fromOverride', () {
      final result = resolveHostingProvider(
        remotes: const <GitRemote>[
          GitRemote(
            name: 'origin',
            url: 'https://github.mycorp.com:8443/t/svc.git',
          ),
        ],
        override: GitHostingProvider.github,
      );
      final resolved = result as HostingProviderResolved;
      expect(resolved.fromOverride, isTrue);
      expect(resolved.identity.provider, GitHostingProvider.github);
      expect(resolved.identity.host, 'github.mycorp.com:8443');
    });

    test('reports no remote when none carry a URL', () {
      final result = resolveHostingProvider(
        remotes: const <GitRemote>[GitRemote(name: 'origin')],
      );
      expect(result, isA<HostingProviderNoRemote>());
    });

    test('auto-detects a GitLab remote', () {
      final result = resolveHostingProvider(
        remotes: const <GitRemote>[
          GitRemote(name: 'origin', url: 'https://gitlab.com/o/r.git'),
        ],
      );
      final resolved = result as HostingProviderResolved;
      expect(resolved.identity.provider, GitHostingProvider.gitlab);
      expect(resolved.identity.owner, 'o');
      expect(resolved.identity.repo, 'r');
    });

    test('reports undetectable for an unrecognized remote', () {
      final result = resolveHostingProvider(
        remotes: const <GitRemote>[
          GitRemote(name: 'origin', url: 'https://codeberg.org/o/r.git'),
        ],
      );
      expect(result, isA<HostingProviderUndetectable>());
    });

    test('reports undetectable with attemptedOverride when override fails', () {
      final result = resolveHostingProvider(
        remotes: const <GitRemote>[
          GitRemote(name: 'origin', url: 'git@example.com:owner/repo.git'),
        ],
        override: GitHostingProvider.azureDevops,
      );
      final undetectable = result as HostingProviderUndetectable;
      expect(undetectable.attemptedOverride, GitHostingProvider.azureDevops);
    });
  });
}
