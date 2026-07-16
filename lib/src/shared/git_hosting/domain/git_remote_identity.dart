import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'git_remote_identity.mapper.dart';

/// Repository coordinates parsed from a git remote URL. GitHub needs
/// [owner]/[repo]; Azure DevOps additionally needs [project] (the org is
/// carried in [owner]). [host] is the remote host (e.g. `github.com`,
/// `dev.azure.com`).
@MappableClass()
class GitRemoteIdentity with GitRemoteIdentityMappable {
  const GitRemoteIdentity({
    required this.provider,
    required this.host,
    required this.owner,
    required this.repo,
    this.project,
  });

  final GitHostingProvider provider;
  final String host;
  final String owner;
  final String repo;
  final String? project;

  factory GitRemoteIdentity.fromJson(Map<String, Object?> json) =>
      GitRemoteIdentityMapper.fromMap(Map<String, dynamic>.from(json));
}
