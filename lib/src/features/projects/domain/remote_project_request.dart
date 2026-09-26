import 'package:alera/src/features/projects/domain/project.dart';

/// Where a project that lives only on a host comes from.
enum RemoteProjectSource {
  /// A folder that already exists on the host.
  existingFolder,

  /// A Git repository the host clones into its own projects folder.
  cloneRepository,
}

/// What `project.registerRemote` needs to create a project on a host. Exactly
/// one of [path] and [cloneUrl] is set.
class const RemoteProjectRequest({
  required final String hostId,
  final String? path,
  final String? cloneUrl,
  final String? name,
  final ProjectKind kind = .gitRepository,
});

/// The request the Add Remote Project form describes, or null while a required
/// field is missing.
///
/// The folder is only required to be non-empty: a Windows host uses drive
/// letters and a POSIX one does not, and the host is what knows which it is. A
/// clone is always a Git project, whatever kind the form held before the
/// source changed.
RemoteProjectRequest? remoteProjectRequestFrom({
  required String? hostId,
  required RemoteProjectSource source,
  required String path,
  required String cloneUrl,
  required String name,
  required ProjectKind kind,
}) {
  final host = hostId?.trim() ?? '';
  if (host.isEmpty || host == 'local') {
    return null;
  }
  final trimmedName = name.trim();
  final resolvedName = trimmedName.isEmpty ? null : trimmedName;
  switch (source) {
    case .existingFolder:
      final folder = path.trim();
      if (folder.isEmpty) {
        return null;
      }
      return RemoteProjectRequest(
        hostId: host,
        path: folder,
        name: resolvedName,
        kind: kind,
      );
    case .cloneRepository:
      final url = cloneUrl.trim();
      if (url.isEmpty) {
        return null;
      }
      return RemoteProjectRequest(
        hostId: host,
        cloneUrl: url,
        name: resolvedName,
      );
  }
}
