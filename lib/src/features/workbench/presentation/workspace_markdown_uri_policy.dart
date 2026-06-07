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
