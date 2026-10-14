/// Where a link in an agent message leads.
sealed class const AgentChatLinkTarget();

/// A web page, opened in the phone's browser.
class const AgentChatExternalLink(final Uri uri) extends AgentChatLinkTarget;

/// A file in the chat's workspace, opened in the workspace file viewer.
class const AgentChatWorkspaceLink(final String path, {final int? line})
    extends AgentChatLinkTarget;

const Set<String> _nonFileSchemes = <String>{
  'about',
  'data',
  'javascript',
  'mailto',
  'sms',
  'tel',
};

final RegExp _fragmentLine = RegExp(r'^L(\d+)(?:-L?\d+)?$');
final RegExp _suffixLine = RegExp(r':(\d+)(?::\d+)?$');

/// Reads a Markdown link from an agent message.
///
/// Agents link files the way their terminal output names them: relative to
/// the working directory, absolute under it, or with a `:line` or `#L12`
/// suffix. Only paths inside [cwd] resolve; anything else on the host is not
/// reachable from the workspace viewer and is ignored rather than guessed.
AgentChatLinkTarget? agentChatLinkTarget(String raw, {String? cwd}) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  final scheme = uri?.scheme.toLowerCase() ?? '';
  if ((scheme == 'http' || scheme == 'https') &&
      (uri?.host.isNotEmpty ?? false)) {
    return AgentChatExternalLink(uri!);
  }
  // `notes.md:12` parses with a scheme of `notes.md`, so only a real URL or a
  // non-file scheme rules a path out.
  if (scheme != 'file' &&
      (value.contains('://') || _nonFileSchemes.contains(scheme))) {
    return null;
  }
  var path = scheme == 'file' ? Uri.decodeComponent(uri!.path) : value;
  int? line;
  final hash = path.lastIndexOf('#');
  if (hash >= 0) {
    line = int.tryParse(
      _fragmentLine.firstMatch(path.substring(hash + 1))?.group(1) ?? '',
    );
    path = path.substring(0, hash);
  }
  final suffix = _suffixLine.firstMatch(path);
  if (suffix != null) {
    line ??= int.tryParse(suffix.group(1)!);
    path = path.substring(0, suffix.start);
  }
  final relative = _workspaceRelative(path.replaceAll(r'\', '/'), cwd);
  if (relative == null) return null;
  return AgentChatWorkspaceLink(relative, line: line);
}

String? _workspaceRelative(String path, String? cwd) {
  var candidate = path;
  final absolute =
      candidate.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(candidate);
  if (absolute) {
    final root = cwd?.replaceAll(r'\', '/').replaceFirst(RegExp(r'/+$'), '');
    if (root == null || root.isEmpty) return null;
    final prefix = '$root/';
    final matches = _windowsPath(root)
        ? candidate.toLowerCase().startsWith(prefix.toLowerCase())
        : candidate.startsWith(prefix);
    if (!matches) return null;
    candidate = candidate.substring(prefix.length);
  }
  final segments = <String>[
    for (final segment in candidate.split('/'))
      if (segment.isNotEmpty && segment != '.') segment,
  ];
  if (segments.isEmpty || segments.contains('..')) return null;
  return segments.join('/');
}

bool _windowsPath(String path) => RegExp(r'^[A-Za-z]:/').hasMatch(path);
