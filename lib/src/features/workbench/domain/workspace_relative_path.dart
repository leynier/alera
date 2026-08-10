import 'package:path/path.dart' as p;

/// Returns [filePath] relative to [workspacePath] when the file lives inside
/// the workspace, or null when it does not. A file equal to the workspace
/// root resolves to '.'.
String? workspaceRelativePath({
  required String workspacePath,
  required String filePath,
  p.Context? pathContext,
}) {
  final context = pathContext ?? p.context;
  if (!context.isAbsolute(filePath)) {
    return null;
  }
  final normalizedWorkspacePath = context.normalize(workspacePath);
  final normalizedFilePath = context.normalize(filePath);
  if (!context.isWithin(normalizedWorkspacePath, normalizedFilePath) &&
      !context.equals(normalizedWorkspacePath, normalizedFilePath)) {
    return null;
  }
  return context.relative(normalizedFilePath, from: normalizedWorkspacePath);
}
