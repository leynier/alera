/// Joins a workspace-relative path onto the host's workspace root.
///
/// The root comes from the paired machine, which may be Windows while the phone
/// is always POSIX, so the separator follows [rootPath] rather than the
/// phone's own path context.
String hostAbsolutePath({
  required String rootPath,
  required String relativePath,
}) {
  final relative = relativePath.replaceAll('\\', '/');
  if (relative.isEmpty) {
    return rootPath;
  }
  final separator = _usesWindowsSeparator(rootPath) ? r'\' : '/';
  final root = rootPath.endsWith(separator)
      ? rootPath.substring(0, rootPath.length - 1)
      : rootPath;
  return <String>[root, ...relative.split('/')].join(separator);
}

bool _usesWindowsSeparator(String rootPath) {
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(rootPath) ||
      rootPath.startsWith(r'\\') ||
      (rootPath.contains(r'\') && !rootPath.contains('/'));
}
