import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';

/// Pure construction of a repository's web (browser) URL from its parsed remote
/// identity. No I/O. Counterpart to [parseGitRemoteIdentity]: one builder per
/// provider, so adding a forge forces the author to decide its web URL shape.

/// The Azure DevOps organization base URL. Legacy `*.visualstudio.com` hosts
/// embed the org in the subdomain; modern hosts use `dev.azure.com/{org}`.
String azureOrgUrl(GitRemoteIdentity identity) {
  if (identity.host.contains('visualstudio.com')) {
    return 'https://${identity.owner}.visualstudio.com';
  }
  return 'https://dev.azure.com/${identity.owner}';
}

/// The repository's home page on its hosting provider, or null when the
/// provider has no web surface (none today: both providers always resolve).
String? repositoryWebUrl(GitRemoteIdentity identity) {
  switch (identity.provider) {
    case GitHostingProvider.github:
      // GitHub and GitHub Enterprise share the same `{host}/{owner}/{repo}`
      // shape; the identity host already carries the enterprise host.
      return 'https://${identity.host}/${identity.owner}/${identity.repo}';
    case GitHostingProvider.gitlab:
      return 'https://${identity.host}/${identity.owner}/${identity.repo}';
    case GitHostingProvider.azureDevops:
      // `project` is always parsed for Azure identities; fall back to the repo
      // name for the rare single-repo project where it could be empty.
      final project = identity.project;
      final effectiveProject = (project == null || project.isEmpty)
          ? identity.repo
          : project;
      return '${azureOrgUrl(identity)}/$effectiveProject/_git/${identity.repo}';
  }
}
