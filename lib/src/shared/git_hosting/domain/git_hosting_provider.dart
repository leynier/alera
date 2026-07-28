import 'package:dart_mappable/dart_mappable.dart';

part 'git_hosting_provider.mapper.dart';

/// Supported git hosting providers ("forges"). New forges (GitLab, Bitbucket,
/// ...) are added here; the rest of the feature dispatches on this enum through
/// the `ForgeProvider` registry, so no provider-specific fields leak elsewhere.
@MappableEnum()
enum GitHostingProvider {
  github,
  azureDevops,
  gitlab;

  /// Human-facing label in title case for UI surfaces.
  String get label => switch (this) {
    GitHostingProvider.github => 'GitHub',
    GitHostingProvider.azureDevops => 'Azure DevOps',
    GitHostingProvider.gitlab => 'GitLab',
  };
}
