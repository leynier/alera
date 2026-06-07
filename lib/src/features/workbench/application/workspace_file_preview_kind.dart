import 'package:path/path.dart' as p;

enum WorkspaceFilePreviewKind { text, image, pdf, merman }

const Set<String> workspaceImageFileExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.ico',
};

const Set<String> workspaceMermanFileExtensions = <String>{'.mermain', '.mmd'};

WorkspaceFilePreviewKind workspaceFilePreviewKindForPath(String filePath) {
  final extension = p.extension(filePath).toLowerCase();
  if (workspaceImageFileExtensions.contains(extension)) {
    return WorkspaceFilePreviewKind.image;
  }
  if (workspaceMermanFileExtensions.contains(extension)) {
    return WorkspaceFilePreviewKind.merman;
  }
  if (extension == '.pdf') {
    return WorkspaceFilePreviewKind.pdf;
  }
  return WorkspaceFilePreviewKind.text;
}

bool isWorkspaceImageFilePath(String filePath) =>
    workspaceFilePreviewKindForPath(filePath) == WorkspaceFilePreviewKind.image;

bool isWorkspacePdfFilePath(String filePath) =>
    workspaceFilePreviewKindForPath(filePath) == WorkspaceFilePreviewKind.pdf;

bool isWorkspaceIcoFilePath(String filePath) =>
    p.extension(filePath).toLowerCase() == '.ico';

bool isWorkspaceMermanFilePath(String filePath) =>
    workspaceFilePreviewKindForPath(filePath) ==
    WorkspaceFilePreviewKind.merman;
