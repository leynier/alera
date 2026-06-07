import 'package:path/path.dart' as p;

enum WorkspaceFilePreviewKind { text, image }

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
  return workspaceImageFileExtensions.contains(extension)
      ? WorkspaceFilePreviewKind.image
      : WorkspaceFilePreviewKind.text;
}

bool isWorkspaceImageFilePath(String filePath) =>
    workspaceFilePreviewKindForPath(filePath) == WorkspaceFilePreviewKind.image;

bool isWorkspaceIcoFilePath(String filePath) =>
    p.extension(filePath).toLowerCase() == '.ico';
