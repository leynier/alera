/// File-name and parent-path labels for mobile file rows.
String workspaceFileBaseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String? workspaceFileDirectory(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  if (index <= 0) {
    return null;
  }
  return normalized.substring(0, index);
}

/// Last [maxSegments] directory segments, so long `lib/src/features/...`
/// prefixes do not dominate a phone row.
String? workspaceFileParentLabel(String path, {int maxSegments = 2}) {
  final directory = workspaceFileDirectory(path);
  if (directory == null || directory.isEmpty) {
    return null;
  }
  final parts = directory
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length <= maxSegments) {
    return directory;
  }
  return parts.sublist(parts.length - maxSegments).join('/');
}
