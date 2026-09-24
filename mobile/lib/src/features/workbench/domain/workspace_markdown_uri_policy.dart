import 'package:path/path.dart' as p;

// Mirrors the desktop Markdown viewer policy
// (lib/src/features/workbench/presentation/workspace_markdown_uri_policy.dart
// and workspace_markdown_viewer_images.dart). alera_mobile cannot import the
// root package, so keep both copies in sync.

bool isWorkspaceMarkdownPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.md') || lower.endsWith('.mdx');
}

bool isSupportedMarkdownViewerLinkUri(Uri? uri) {
  return _isSupportedMarkdownViewerWebUri(uri);
}

bool isSupportedMarkdownViewerRemoteImageUri(Uri? uri) {
  return _isSupportedMarkdownViewerWebUri(uri);
}

bool _isSupportedMarkdownViewerWebUri(Uri? uri) {
  if (uri == null || uri.host.trim().isEmpty) {
    return false;
  }
  return switch (uri.scheme.toLowerCase()) {
    'http' || 'https' => true,
    _ => false,
  };
}

/// Resolves an image reference relative to [markdownPath] into a
/// workspace-relative POSIX path, or null when it names anything other than a
/// plain relative file inside the workspace.
String? resolveWorkspaceMarkdownImagePath({
  required String markdownPath,
  required String rawImageUrl,
}) {
  final trimmed = rawImageUrl.trim();
  if (trimmed.isEmpty ||
      trimmed.startsWith('/') ||
      trimmed.startsWith(r'\') ||
      trimmed.startsWith('//') ||
      _startsWithWindowsDrive(trimmed)) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return null;
  }

  final decodedPath = _decodeMarkdownImagePath(uri.path)?.replaceAll(r'\', '/');
  if (decodedPath == null ||
      decodedPath.isEmpty ||
      decodedPath.startsWith('/') ||
      _startsWithWindowsDrive(decodedPath)) {
    return null;
  }

  final markdownDirectory = p.posix.dirname(markdownPath);
  final joined = markdownDirectory == '.'
      ? decodedPath
      : p.posix.join(markdownDirectory, decodedPath);
  final normalized = p.posix.normalize(joined);
  if (normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      p.posix.isAbsolute(normalized)) {
    return null;
  }
  return normalized;
}

String? _decodeMarkdownImagePath(String path) {
  try {
    return Uri.decodeFull(path);
  } on FormatException {
    return null;
  }
}

bool _startsWithWindowsDrive(String path) {
  return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);
}
