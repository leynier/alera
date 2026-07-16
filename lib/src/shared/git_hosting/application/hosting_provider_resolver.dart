import 'package:alera/src/shared/git_hosting/application/git_remote_parser.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/git/git_remote.dart';

/// Typed outcome of resolving which hosting provider a repository belongs to.
/// Never a bare null: callers switch over the concrete cases.
sealed class HostingProviderResolution {
  const HostingProviderResolution();
}

/// The provider and repository coordinates were resolved. [fromOverride] is
/// true when a project-level provider override forced the interpretation.
class HostingProviderResolved extends HostingProviderResolution {
  const HostingProviderResolved({
    required this.identity,
    required this.fromOverride,
  });

  final GitRemoteIdentity identity;
  final bool fromOverride;
}

/// A usable remote URL exists but could not be interpreted. When
/// [attemptedOverride] is set, the failure is against a forced provider.
class HostingProviderUndetectable extends HostingProviderResolution {
  const HostingProviderUndetectable({this.remoteUrl, this.attemptedOverride});

  final String? remoteUrl;
  final GitHostingProvider? attemptedOverride;
}

/// The repository has no remote with a URL to resolve against.
class HostingProviderNoRemote extends HostingProviderResolution {
  const HostingProviderNoRemote();
}

/// Resolves the effective hosting provider from the repository's [remotes] and
/// an optional project-level [override]. Precedence: the override forces the
/// provider (coordinates still come from the remote URL); otherwise the
/// provider is auto-detected from the remote host.
HostingProviderResolution resolveHostingProvider({
  required List<GitRemote> remotes,
  GitHostingProvider? override,
}) {
  final url = _preferredRemoteUrl(remotes);
  if (url == null || url.isEmpty) {
    return const HostingProviderNoRemote();
  }
  if (override != null) {
    final identity = parseRemoteAsProvider(url, override);
    if (identity != null) {
      return HostingProviderResolved(identity: identity, fromOverride: true);
    }
    return HostingProviderUndetectable(
      remoteUrl: url,
      attemptedOverride: override,
    );
  }
  final identity = parseGitRemoteIdentity(url);
  if (identity != null) {
    return HostingProviderResolved(identity: identity, fromOverride: false);
  }
  return HostingProviderUndetectable(remoteUrl: url);
}

/// Prefers `origin`, then `upstream`, then the first remote with a URL.
String? _preferredRemoteUrl(List<GitRemote> remotes) {
  String? firstWithUrl;
  String? upstream;
  for (final remote in remotes) {
    final url = remote.url;
    if (url == null || url.isEmpty) {
      continue;
    }
    if (remote.name == 'origin') {
      return url;
    }
    if (remote.name == 'upstream') {
      upstream ??= url;
    }
    firstWithUrl ??= url;
  }
  return upstream ?? firstWithUrl;
}
