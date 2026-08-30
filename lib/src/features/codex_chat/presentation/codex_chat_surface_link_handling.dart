part of 'codex_chat_surface.dart';

class const _CodexLinkScope({
  required final Future<void> Function(String rawLink) onOpenLink,
  required super.child,
}) extends InheritedWidget {
  static _CodexLinkScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CodexLinkScope>();

  @override
  bool updateShouldNotify(_CodexLinkScope oldWidget) =>
      onOpenLink != oldWidget.onOpenLink;
}

extension _CodexMarkdownLinkActions on _CodexChatSurfaceState {
  Future<void> _openMarkdownLink(String rawLink) async {
    final value = rawLink.trim();
    final uri = Uri.tryParse(value);
    if (_isCodexWebLink(uri)) {
      await _launchMarkdownUri(uri!);
      return;
    }
    final target = resolveCodexMarkdownFileTarget(
      workspacePath: _activeCodexWorkspacePath,
      rawLink: value,
    );
    if (target != null) {
      final type = await FileSystemEntity.type(target.path, followLinks: true);
      if (type != FileSystemEntityType.notFound) {
        await _openAttachment(
          target.path,
          isImage: isCodexImagePath(target.path),
          line: target.line,
        );
        return;
      }
      _showMarkdownLinkError();
      return;
    }
    if (codexShouldLaunchExternalUri(value, uri)) {
      await _launchMarkdownUri(uri!);
      return;
    }
    _showMarkdownLinkError();
  }

  Future<void> _launchMarkdownUri(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: .externalApplication);
      if (!opened) _showMarkdownLinkError();
    } catch (_) {
      _showMarkdownLinkError();
    }
  }

  void _showMarkdownLinkError() {
    if (!mounted) return;
    AleraToast.show(context, message: 'Link cannot be opened', tone: .error);
  }
}

bool _isCodexWebLink(Uri? uri) =>
    uri != null &&
    uri.host.trim().isNotEmpty &&
    (uri.scheme.toLowerCase() == 'http' || uri.scheme.toLowerCase() == 'https');

@visibleForTesting
bool codexShouldLaunchExternalUri(String rawLink, Uri? uri) {
  if (uri == null ||
      _isWindowsAbsoluteCodexPath(rawLink) ||
      p.isAbsolute(rawLink)) {
    return false;
  }
  return switch (uri.scheme.toLowerCase()) {
    'http' || 'https' => uri.host.trim().isNotEmpty,
    'mailto' || 'tel' || 'sms' => true,
    _ => false,
  };
}

@visibleForTesting
String? resolveCodexMarkdownFilePath({
  required String workspacePath,
  required String rawLink,
}) => resolveCodexMarkdownFileTarget(
  workspacePath: workspacePath,
  rawLink: rawLink,
)?.path;

@visibleForTesting
CodexMarkdownFileTarget? resolveCodexMarkdownFileTarget({
  required String workspacePath,
  required String rawLink,
}) {
  final value = rawLink.trim();
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (_isCodexWebLink(uri)) return null;
  final compactLineReference = RegExp(r'^([^/\\:]+):(\d+)(?::\d+)?$')
      .firstMatch(value);
  if (compactLineReference != null) {
    String decodedReference;
    try {
      decodedReference = Uri.decodeComponent(value);
    } on FormatException {
      return null;
    }
    final target = _codexMarkdownTargetFromPath(decodedReference);
    if (target == null) return null;
    return CodexMarkdownFileTarget(
      path: p.normalize(p.join(workspacePath, target.path)),
      line: target.line,
    );
  }
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() == 'file') {
    try {
      final fragment = uri.fragment;
      final path = uri
          .replace(fragment: '')
          .toFilePath(windows: Platform.isWindows);
      return _codexMarkdownTargetFromPath(path, fragment: fragment);
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }
  if (_isWindowsAbsoluteCodexPath(value)) {
    final fragmentStart = value.indexOf('#');
    final encodedPath = fragmentStart < 0
        ? value
        : value.substring(0, fragmentStart);
    final fragment = fragmentStart < 0
        ? ''
        : value.substring(fragmentStart + 1);
    String decodedPath;
    try {
      decodedPath = Uri.decodeComponent(encodedPath);
    } on FormatException {
      return null;
    }
    final target = _codexMarkdownTargetFromPath(
      decodedPath,
      fragment: fragment,
    );
    if (target == null) return null;
    return CodexMarkdownFileTarget(
      path: p.windows.normalize(target.path),
      line: target.line,
    );
  }
  if (p.isAbsolute(value)) {
    String decodedPath;
    try {
      decodedPath = Uri.decodeComponent(uri.path);
    } on FormatException {
      return null;
    }
    return _codexMarkdownTargetFromPath(decodedPath, fragment: uri.fragment);
  }
  if (uri.scheme.isNotEmpty || uri.host.isNotEmpty) return null;
  String decodedPath;
  try {
    decodedPath = Uri.decodeComponent(uri.path);
  } on FormatException {
    return null;
  }
  if (decodedPath.trim().isEmpty) return null;
  final target = _codexMarkdownTargetFromPath(
    decodedPath,
    fragment: uri.fragment,
  );
  if (target == null) return null;
  return CodexMarkdownFileTarget(
    path: p.normalize(
      p.isAbsolute(target.path)
          ? target.path
          : p.join(workspacePath, target.path),
    ),
    line: target.line,
  );
}

bool _isWindowsAbsoluteCodexPath(String value) =>
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) || value.startsWith(r'\\');

CodexMarkdownFileTarget? _codexMarkdownTargetFromPath(
  String rawPath, {
  String fragment = '',
}) {
  var path = rawPath;
  int? line;
  final lineSuffix = RegExp(r'^(.*?):(\d+)(?::\d+)?$').firstMatch(path);
  if (lineSuffix != null && lineSuffix.group(1)!.trim().isNotEmpty) {
    path = lineSuffix.group(1)!;
    final parsedLine = int.tryParse(lineSuffix.group(2)!);
    if (parsedLine != null && parsedLine > 0) line = parsedLine;
  }
  final fragmentLine = RegExp(
    r'^L(\d+)(?:-L\d+)?$',
    caseSensitive: false,
  ).firstMatch(fragment);
  final parsedFragmentLine = fragmentLine == null
      ? null
      : int.tryParse(fragmentLine.group(1)!);
  if (line == null && parsedFragmentLine != null && parsedFragmentLine > 0) {
    line = parsedFragmentLine;
  }
  if (path.trim().isEmpty) return null;
  return CodexMarkdownFileTarget(path: p.normalize(path), line: line);
}

@visibleForTesting
class const CodexMarkdownFileTarget({
  required final String path,
  final int? line,
});
