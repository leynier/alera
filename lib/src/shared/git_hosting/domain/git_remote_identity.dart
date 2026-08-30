import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'git_remote_identity.mapper.dart';

/// Repository coordinates parsed from a git remote URL. GitHub and GitLab need
/// [owner]/[repo] (GitLab's owner can contain nested groups); Azure DevOps
/// additionally needs [project] (the org is carried in [owner]). [host] is the
/// remote host (e.g. `github.com`, `gitlab.com`, `dev.azure.com`).
@MappableClass()
class const GitRemoteIdentity({
  required this.provider,
  required this.host,
  required this.owner,
  required this.repo,
  this.project,
}) with GitRemoteIdentityMappable {
  final GitHostingProvider provider;
  final String host;
  final String owner;
  final String repo;
  final String? project;

  factory fromJson(Map<String, Object?> json) =>
      GitRemoteIdentityMapper.fromMap(Map<String, dynamic>.from(json));
}
