import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:path/path.dart' as p;

Future<bool> openTerminalComposerWorkspaceAttachment({
  required String workspacePath,
  required String filePath,
  required WorkspaceFileService workspaceFiles,
  required Future<void> Function(String relativePath) openFile,
}) async {
  final relativePath = terminalComposerWorkspaceRelativePath(
    workspacePath: workspacePath,
    filePath: filePath,
  );
  if (relativePath == null) {
    return false;
  }

  try {
    switch (workspaceFilePreviewKindForPath(relativePath)) {
      case WorkspaceFilePreviewKind.image:
      case WorkspaceFilePreviewKind.pdf:
        await workspaceFiles.resolveWorkspaceFilePath(
          workspacePath: workspacePath,
          relativePath: relativePath,
        );
      case WorkspaceFilePreviewKind.text:
      case WorkspaceFilePreviewKind.merman:
        await workspaceFiles.readTextFile(
          workspacePath: workspacePath,
          relativePath: relativePath,
        );
    }
  } on native.WorkspaceFileError {
    return false;
  }

  await openFile(relativePath);
  return true;
}

String? terminalComposerWorkspaceRelativePath({
  required String workspacePath,
  required String filePath,
}) {
  if (!p.isAbsolute(filePath)) {
    return null;
  }
  final normalizedWorkspacePath = p.normalize(workspacePath);
  final normalizedFilePath = p.normalize(filePath);
  if (!p.isWithin(normalizedWorkspacePath, normalizedFilePath)) {
    return null;
  }
  return p.relative(normalizedFilePath, from: normalizedWorkspacePath);
}
