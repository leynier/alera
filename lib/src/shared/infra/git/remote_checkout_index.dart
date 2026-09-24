import 'package:path/path.dart' as p;

/// One checkout that lives on another host: the workspace whose `git.*`
/// requests the runtime forwards, and the path that checkout has *there*.
class const RemoteCheckoutEntry({
  required final String workspaceId,
  required final String path,
});

/// Maps a git path to the remote workspace whose checkout contains it, so a
/// caller that only knows a path (the Source Control root, a diff tab, the
/// explorer) still reaches the right host without carrying the workspace.
///
/// A path is remote only when it is inside a remote checkout and inside no
/// local one: the same string can be a valid path on both machines (two Linux
/// homes with the same layout), and a local checkout that exists must win,
/// because the local bridge is what the user sees on disk.
///
/// Remote paths are compared with the path style they are written in, since a
/// Windows checkout keeps its drive letter and backslashes on a POSIX hub.
class RemoteCheckoutIndex {
  new(Iterable<RemoteCheckoutEntry> remote, Iterable<String> local)
    : _remote = List.unmodifiableOf(remote),
      _local = List.unmodifiableOf(local);

  const new empty() : _remote = const [], _local = const [];

  final List<RemoteCheckoutEntry> _remote;
  final List<String> _local;

  bool get isEmpty => _remote.isEmpty;

  String? remoteWorkspaceIdFor(String path) {
    if (_remote.isEmpty) {
      return null;
    }
    final context = _contextFor(path);
    for (final localPath in _local) {
      if (_contains(context, localPath, path)) {
        return null;
      }
    }
    RemoteCheckoutEntry? best;
    for (final entry in _remote) {
      if (!_contains(context, entry.path, path)) {
        continue;
      }
      if (best == null || entry.path.length > best.path.length) {
        best = entry;
      }
    }
    return best?.workspaceId;
  }

  static bool _contains(p.Context context, String root, String candidate) {
    if (_contextFor(root) != context) {
      return false;
    }
    final normalizedRoot = context.normalize(root);
    final normalizedCandidate = context.normalize(candidate);
    return context.equals(normalizedRoot, normalizedCandidate) ||
        context.isWithin(normalizedRoot, normalizedCandidate);
  }

  static p.Context _contextFor(String path) {
    final looksWindows =
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');
    return looksWindows ? p.windows : p.posix;
  }
}
