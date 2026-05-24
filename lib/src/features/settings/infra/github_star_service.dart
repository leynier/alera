import 'dart:async';

import 'package:alera/src/shared/infra/process/process_runner.dart';

const String aleraGitHubOwner = 'leynier';
const String aleraGitHubRepo = 'alera';
const String aleraGitHubUrl =
    'https://github.com/$aleraGitHubOwner/$aleraGitHubRepo';

/// Thin wrapper around the `gh` CLI for star detection / starring the Alera
/// repo. Mirrors the Orca pattern: returns `null` whenever `gh` is unavailable
/// or unauthenticated so the caller can hide the feature gracefully.
class GitHubStarService {
  GitHubStarService(this._processRunner);

  final ProcessRunner _processRunner;

  Future<void> _serialize = Future<void>.value();

  Future<T> _withLock<T>(Future<T> Function() body) {
    final previous = _serialize;
    final completer = Completer<void>();
    _serialize = completer.future;
    return previous.then((_) async {
      try {
        return await body();
      } finally {
        completer.complete();
      }
    });
  }

  static const String _starredPath =
      'user/starred/$aleraGitHubOwner/$aleraGitHubRepo';

  /// Returns `true` if the authenticated user has starred the repo, `false`
  /// if not, and `null` when `gh` is missing, unauthenticated, or unreachable.
  Future<bool?> checkStarred() {
    return _withLock(() async {
      try {
        final result = await _processRunner.run('gh', const <String>[
          'api',
          '--silent',
          '-i',
          _starredPath,
        ]);
        if (result.exitCode == 0) {
          return true;
        }
        if (_isNotFound(result.stderr) || _isNotFound(result.stdout)) {
          return false;
        }
        return null;
      } catch (_) {
        return null;
      }
    });
  }

  /// Stars the repo on behalf of the authenticated user. Returns `true` on
  /// success, `false` on a clean failure (gh returned non-zero).
  Future<bool> star() {
    return _withLock(() async {
      try {
        final result = await _processRunner.run('gh', const <String>[
          'api',
          '--silent',
          '-X',
          'PUT',
          _starredPath,
        ]);
        return result.exitCode == 0;
      } catch (_) {
        return false;
      }
    });
  }

  bool _isNotFound(String output) {
    final lower = output.toLowerCase();
    return lower.contains('http 404') || lower.contains('status: 404');
  }
}
