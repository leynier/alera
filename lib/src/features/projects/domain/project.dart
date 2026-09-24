import 'package:dart_mappable/dart_mappable.dart';

part 'project.mapper.dart';

@MappableEnum()
enum ProjectKind { gitRepository, folder }

/// Where a project lives on one host. The runtime lists one per host the
/// project was added to; `local` is this device.
@MappableClass()
class const ProjectCheckout({required this.hostId, required this.path})
    with ProjectCheckoutMappable {
  final String hostId;
  final String path;
}

@MappableClass()
class const Project({
  required this.id,
  required this.name,
  required this.repoPath,
  required this.createdAt,
  required this.updatedAt,
  this.kind = ProjectKind.gitRepository,
  this.primaryHostId = 'local',
  this.checkouts = const <ProjectCheckout>[],
}) with ProjectMappable {
  final String id;
  final String name;
  final String repoPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ProjectKind kind;

  /// The host of [repoPath]. Anything but `local` means the project has no
  /// folder on this device, so [repoPath] is a path on that host and MUST NOT
  /// be read as a local directory. Absent from an older runtime, which only
  /// knows local projects.
  final String primaryHostId;

  /// Every host the project is on. Empty from an older runtime.
  final List<ProjectCheckout> checkouts;

  bool get isRemoteOnly => primaryHostId != 'local';

  /// Whether the project already has a checkout on [hostId] (`null` or blank
  /// means this device), which is what New Workspace needs before it can list
  /// branches or create a workspace there.
  bool isOnHost(String? hostId) {
    final host = hostId == null || hostId.trim().isEmpty ? 'local' : hostId;
    if (host == primaryHostId) {
      return true;
    }
    return checkouts.any((checkout) => checkout.hostId == host);
  }

  bool get isGitRepository => kind == ProjectKind.gitRepository;

  bool get isFolder => kind == ProjectKind.folder;

  bool get supportsLinkedWorkspaces => isGitRepository;

  factory fromJson(Map<String, Object?> json) =>
      ProjectMapper.fromMap(Map<String, dynamic>.from(json));
}
