import 'dart:async';

/// The workspace files the composer's `@` mentions search.
abstract interface class AgentChatComposerFileSearch {
  /// Names the file tree; a different key drops the open search session.
  String get key;

  Future<AgentChatComposerFileSearchSession> open();

  /// The path attached for a [relativePath] the search returned.
  String attachmentPath(String relativePath);
}

/// One open search over a file tree, closed when the menu closes.
abstract interface class AgentChatComposerFileSearchSession {
  /// Workspace-relative paths matching [query], best match first.
  Future<List<String>> search(String query, {required int limit});

  Future<void> close();
}

const Duration _searchDebounce = Duration(milliseconds: 120);
const int _searchLimit = 50;

final class _StaleSearch implements Exception {
  const _StaleSearch();
}

/// The results of the `@` mention being typed. A query waits [debounce]
/// before it searches, so typing a path does not start a search per key, and
/// a result that arrives after a newer query, another file tree, or [reset]
/// is dropped.
///
/// It is plain Dart so the desktop and the phone share it; listeners hear
/// every change, as with a Flutter `ChangeNotifier`.
class AgentChatComposerMentionSearch {
  AgentChatComposerMentionSearch({
    this.debounce = _searchDebounce,
    this.limit = _searchLimit,
  });

  final Duration debounce;
  final int limit;
  final List<void Function()> _listeners = <void Function()>[];

  AgentChatComposerFileSearch? _source;
  AgentChatComposerFileSearchSession? _session;
  Future<AgentChatComposerFileSearchSession>? _opening;
  Timer? _timer;
  int _generation = 0;
  String? _query;
  List<String> _results = const <String>[];
  bool _loading = false;
  Object? _error;
  bool _disposed = false;

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  /// Workspace-relative paths for the latest query that finished.
  List<String> get results => _results;

  /// A query is waiting or searching; [results] still holds the last one.
  bool get loading => _loading;

  /// Why the latest query failed, if it did.
  Object? get error => _error;

  void search(AgentChatComposerFileSearch source, String query) {
    if (_disposed) return;
    if (_source?.key != source.key) {
      _closeSession();
      _query = null;
      _results = const <String>[];
    }
    _source = source;
    if (query == _query) return;
    _query = query;
    _loading = true;
    _error = null;
    final generation = ++_generation;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(_run(source, query, generation)));
    _notify();
  }

  /// Forgets the query and closes the session, so the next mention searches
  /// a fresh index.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    _closeSession();
    final changed = _query != null || _results.isNotEmpty || _loading;
    _query = null;
    _results = const <String>[];
    _loading = false;
    _error = null;
    if (changed && !_disposed) _notify();
  }

  Future<void> _run(
    AgentChatComposerFileSearch source,
    String query,
    int generation,
  ) async {
    try {
      final session = await _sessionFor(source);
      if (generation != _generation) return;
      final results = await session.search(query, limit: limit);
      if (_disposed ||
          generation != _generation ||
          !identical(session, _session)) {
        return;
      }
      _results = results;
      _loading = false;
      _notify();
    } on Object catch (error) {
      if (_disposed || generation != _generation || error is _StaleSearch) {
        return;
      }
      _results = const <String>[];
      _error = error;
      _loading = false;
      _notify();
    }
  }

  Future<AgentChatComposerFileSearchSession> _sessionFor(
    AgentChatComposerFileSearch source,
  ) async {
    final existing = _session;
    if (existing != null) return existing;
    final opening = _opening ??= source.open();
    try {
      final session = await opening;
      // Another search awaiting the same opening may have kept it already.
      if (identical(_session, session)) return session;
      if (_disposed || !identical(_opening, opening)) {
        unawaited(_closeQuietly(session));
        throw const _StaleSearch();
      }
      _session = session;
      return session;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  void _closeSession() {
    final session = _session;
    _session = null;
    // A session still opening is closed by the search awaiting it.
    _opening = null;
    if (session != null) unawaited(_closeQuietly(session));
  }

  static Future<void> _closeQuietly(
    AgentChatComposerFileSearchSession session,
  ) async {
    try {
      await session.close();
    } on Object {
      // Closing is best effort, as it is for Quick Open.
    }
  }

  void dispose() {
    _disposed = true;
    reset();
    _listeners.clear();
  }
}
