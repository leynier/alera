import 'package:path/path.dart' as p;

enum WorkspaceFilePreviewKind { text, image, pdf }

const Set<String> workspaceImageFileExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.ico',
};

WorkspaceFilePreviewKind workspaceFilePreviewKindForPath(String filePath) {
  final extension = p.extension(filePath).toLowerCase();
  if (workspaceImageFileExtensions.contains(extension)) {
    return WorkspaceFilePreviewKind.image;
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
