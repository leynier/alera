import 'package:alera/src/shared/git_hosting/application/git_remote_parser.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/git/git_remote.dart';

/// Typed outcome of resolving which hosting provider a repository belongs to.
/// Never a bare null: callers switch over the concrete cases.
sealed class const HostingProviderResolution();

/// The provider and repository coordinates were resolved. [fromOverride] is
/// true when a project-level provider override forced the interpretation.
class const HostingProviderResolved({
  required final GitRemoteIdentity identity,
  required final bool fromOverride,
}) extends HostingProviderResolution;

/// A usable remote URL exists but could not be interpreted. When
/// [attemptedOverride] is set, the failure is against a forced provider.
class const HostingProviderUndetectable({
  final String? remoteUrl,
  final GitHostingProvider? attemptedOverride,
}) extends HostingProviderResolution;

/// The repository has no remote with a URL to resolve against.
class const HostingProviderNoRemote() extends HostingProviderResolution;

/// Resolves the effective hosting provider from the repository's [remotes] and
/// an optional project-level [override]. Precedence: the override forces the
/// provider (coordinates still come from the remote URL); otherwise the
/// provider is auto-detected from the remote host.
HostingProviderResolution resolveHostingProvider({
  required List<GitRemote> remotes,
  GitHostingProvider? override,
}) {
  final url = _preferredRemote(remotes)?.url;
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

String? preferredHostingRemoteName(List<GitRemote> remotes) {
  return _preferredRemote(remotes)?.name;
}

/// Prefers `origin`, then `upstream`, then the first remote with a URL.
GitRemote? _preferredRemote(List<GitRemote> remotes) {
  GitRemote? firstWithUrl;
  GitRemote? upstream;
  for (final remote in remotes) {
    final url = remote.url;
    if (url == null || url.isEmpty) {
      continue;
    }
    if (remote.name == 'origin') {
      return remote;
    }
    if (remote.name == 'upstream') {
      upstream ??= remote;
    }
    firstWithUrl ??= remote;
  }
  return upstream ?? firstWithUrl;
}
