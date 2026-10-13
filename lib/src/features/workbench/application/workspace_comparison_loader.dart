import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';

/// Serializes expensive comparisons and merges revisions received mid-flight.
class WorkspaceComparisonLoader({
  required final Future<GitWorkspaceComparison> Function() loadSnapshot,
}) {
  Future<GitWorkspaceComparison>? _inFlight;
  GitWorkspaceComparison? _snapshot;
  int _requestedRevision = 0;
  int _completedRevision = -1;
  bool _disposed = false;

  Future<GitWorkspaceComparison> load(int revision) {
    if (_disposed) {
      throw StateError('Workspace comparison is no longer observed.');
    }
    if (revision > _requestedRevision) _requestedRevision = revision;
    final cached = _snapshot;
    if (_inFlight == null && cached != null && _completedRevision >= revision) {
      return Future.value(cached);
    }
    return _inFlight ??= _drain().whenComplete(() => _inFlight = null);
  }

  Future<GitWorkspaceComparison> _drain() async {
    do {
      final revision = _requestedRevision;
      _snapshot = await loadSnapshot();
      _completedRevision = revision;
    } while (!_disposed && _completedRevision < _requestedRevision);
    return _snapshot!;
  }

  void dispose() => _disposed = true;
}
