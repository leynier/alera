import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_view_prefs_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:alera_mobile/src/features/workbench/domain/workspace_search_rows.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_text_search_controller.g.dart';

const Duration _searchDebounce = Duration(milliseconds: 250);
final Logger _log = Logger('WorkspaceTextSearchController');

class const WorkspaceTextSearchState({
  final String query = '',
  final String replacement = '',
  final bool caseSensitive = false,
  final bool wholeWord = false,
  final bool useRegex = false,
  final bool preserveCase = false,
  final bool includeIgnored = false,
  final bool viewAsTree = false,
  final String includePattern = '',
  final String excludePattern = '',
  final MobileWorkspaceSearchResult? result,
  final Object? error,
  final bool searching = false,
  final bool replacing = false,
  final Set<String> collapsedResultNodeKeys = const <String>{},
}) {
  bool get hasQuery => query.trim().isNotEmpty;

  MobileWorkspaceSearchQuery get searchQuery => MobileWorkspaceSearchQuery(
    query: query.trim(),
    caseSensitive: caseSensitive,
    wholeWord: wholeWord,
    useRegex: useRegex,
    includePattern: includePattern,
    excludePattern: excludePattern,
    includeIgnored: includeIgnored,
  );

  bool get canReplace =>
      hasQuery && !searching && !replacing && (result?.totalMatches ?? 0) > 0;

  /// The host refuses Replace All on a truncated result, because the matches
  /// the phone never saw would be replaced too.
  bool get canReplaceAll => canReplace && result?.truncated != true;

  bool get allResultsCollapsed {
    final keys = workspaceSearchCollapsibleNodeKeys(
      result,
      viewAsTree: viewAsTree,
    );
    return keys.isNotEmpty && keys.every(collapsedResultNodeKeys.contains);
  }

  WorkspaceTextSearchState copyWith({
    String? query,
    String? replacement,
    bool? caseSensitive,
    bool? wholeWord,
    bool? useRegex,
    bool? preserveCase,
    bool? includeIgnored,
    bool? viewAsTree,
    String? includePattern,
    String? excludePattern,
    Object? result = _sentinel,
    Object? error = _sentinel,
    bool? searching,
    bool? replacing,
    Set<String>? collapsedResultNodeKeys,
  }) {
    return WorkspaceTextSearchState(
      query: query ?? this.query,
      replacement: replacement ?? this.replacement,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      wholeWord: wholeWord ?? this.wholeWord,
      useRegex: useRegex ?? this.useRegex,
      preserveCase: preserveCase ?? this.preserveCase,
      includeIgnored: includeIgnored ?? this.includeIgnored,
      viewAsTree: viewAsTree ?? this.viewAsTree,
      includePattern: includePattern ?? this.includePattern,
      excludePattern: excludePattern ?? this.excludePattern,
      result: identical(result, _sentinel)
          ? this.result
          : result as MobileWorkspaceSearchResult?,
      error: identical(error, _sentinel) ? this.error : error,
      searching: searching ?? this.searching,
      replacing: replacing ?? this.replacing,
      collapsedResultNodeKeys:
          collapsedResultNodeKeys ?? this.collapsedResultNodeKeys,
    );
  }
}

const Object _sentinel = Object();

@riverpod
class WorkspaceTextSearchController extends _$WorkspaceTextSearchController {
  Timer? _debounce;
  var _generation = 0;
  String? _activeRequestId;

  @override
  WorkspaceTextSearchState build(String hostId, String workspaceId) {
    ref.onDispose(() {
      _debounce?.cancel();
      _cancelActiveRequest();
    });
    // View as tree and Search ignored files are shared with the desktop
    // through the runtime view prefs; an older host without them keeps the
    // local defaults.
    ref.listen(mobileViewPrefsControllerProvider(hostId), (_, next) {
      if (next.value case final prefs?) {
        _applyViewPrefs(prefs);
      }
    });
    final prefs = ref.read(mobileViewPrefsControllerProvider(hostId)).value;
    return WorkspaceTextSearchState(
      viewAsTree: prefs?.searchViewAsTree ?? false,
      includeIgnored: prefs?.searchIncludeIgnored ?? false,
    );
  }

  void setQuery(String value) => _changeInput(state.copyWith(query: value));

  void setReplacement(String value) =>
      _changeInput(state.copyWith(replacement: value));

  void setIncludePattern(String value) =>
      _changeInput(state.copyWith(includePattern: value));

  void setExcludePattern(String value) =>
      _changeInput(state.copyWith(excludePattern: value));

  void toggleCaseSensitive() =>
      _changeInput(state.copyWith(caseSensitive: !state.caseSensitive));

  void toggleWholeWord() =>
      _changeInput(state.copyWith(wholeWord: !state.wholeWord));

  void toggleUseRegex() =>
      _changeInput(state.copyWith(useRegex: !state.useRegex));

  void togglePreserveCase() =>
      _changeInput(state.copyWith(preserveCase: !state.preserveCase));

  void toggleIncludeIgnored() {
    final next = !state.includeIgnored;
    _changeInput(state.copyWith(includeIgnored: next));
    _persist((controller) => controller.setSearchIncludeIgnored(next));
  }

  void toggleViewAsTree() {
    final next = !state.viewAsTree;
    state = state.copyWith(viewAsTree: next);
    _persist((controller) => controller.setSearchViewAsTree(next));
  }

  void toggleResultNodeCollapsed(String nodeKey) {
    final next = <String>{...state.collapsedResultNodeKeys};
    if (!next.remove(nodeKey)) {
      next.add(nodeKey);
    }
    state = state.copyWith(collapsedResultNodeKeys: next);
  }

  void toggleAllResultsCollapsed() {
    final keys = workspaceSearchCollapsibleNodeKeys(
      state.result,
      viewAsTree: state.viewAsTree,
    );
    if (keys.isEmpty) {
      return;
    }
    state = state.copyWith(
      collapsedResultNodeKeys: state.allResultsCollapsed
          ? const <String>{}
          : keys,
    );
  }

  void clear() {
    _debounce?.cancel();
    _cancelActiveRequest();
    _generation += 1;
    state = WorkspaceTextSearchState(
      caseSensitive: state.caseSensitive,
      wholeWord: state.wholeWord,
      useRegex: state.useRegex,
      preserveCase: state.preserveCase,
      includeIgnored: state.includeIgnored,
      viewAsTree: state.viewAsTree,
    );
  }

  Future<void> runNow() async {
    _debounce?.cancel();
    _cancelActiveRequest();
    final generation = ++_generation;
    if (!state.hasQuery) {
      state = state.copyWith(result: null, error: null, searching: false);
      return;
    }
    state = state.copyWith(searching: true, error: null);
    final requestId = '$workspaceId:$generation';
    try {
      final panels = await _panels();
      if (generation != _generation) {
        return;
      }
      if (panels == null || !panels.supportsWorkspaceSearch) {
        state = state.copyWith(
          searching: false,
          result: null,
          error: 'Update the paired Alera runtime to search the workspace.',
        );
        return;
      }
      _activeRequestId = panels.supportsWorkspaceReplace ? requestId : null;
      final search = state.searchQuery;
      final result = await panels.searchWorkspace(
        workspaceId: workspaceId,
        query: search.query,
        caseSensitive: search.caseSensitive,
        wholeWord: search.wholeWord,
        useRegex: search.useRegex,
        includePattern: search.includePattern,
        excludePattern: search.excludePattern,
        includeIgnored: search.includeIgnored,
        replacement: state.replacement,
        preserveCase: state.preserveCase,
        requestId: requestId,
      );
      if (generation != _generation) {
        return;
      }
      state = state.copyWith(result: result, error: null, searching: false);
    } on Object catch (error, stackTrace) {
      if (generation != _generation) {
        return;
      }
      _log.warning('workspace search failed', error, stackTrace);
      state = state.copyWith(result: null, error: error, searching: false);
    } finally {
      if (_activeRequestId == requestId) {
        _activeRequestId = null;
      }
    }
  }

  /// Replaces [matchIds], or every match when empty. Each affected file's
  /// content token from the last search goes along, so the host skips any file
  /// that changed on disk since the phone saw it instead of overwriting it.
  Future<MobileWorkspaceReplaceResult> replaceMatches(
    Iterable<String> matchIds,
  ) async {
    final result = state.result;
    if (result == null) {
      throw StateError('Run search before replacing.');
    }
    final selected = matchIds.toSet();
    if (selected.isEmpty && result.truncated) {
      throw StateError(
        'Replace all is unavailable while results are truncated.',
      );
    }
    final panels = await _panels();
    if (panels == null || !panels.supportsWorkspaceReplace) {
      throw UnsupportedError(
        'Update the paired Alera runtime to replace workspace matches.',
      );
    }
    final affected = selected.isEmpty
        ? result.files
        : <MobileWorkspaceSearchFile>[
            for (final file in result.files)
              if (file.matches.any((match) => selected.contains(match.id)))
                file,
          ];
    state = state.copyWith(replacing: true, error: null);
    try {
      final replaced = await panels.replaceWorkspaceMatches(
        workspaceId: workspaceId,
        search: state.searchQuery,
        replacement: state.replacement,
        preserveCase: state.preserveCase,
        matchIds: selected.toList(growable: false),
        expectedFiles: affected,
      );
      state = state.copyWith(replacing: false);
      unawaited(runNow());
      return replaced;
    } on Object catch (error, stackTrace) {
      _log.warning('workspace replace failed', error, stackTrace);
      state = state.copyWith(replacing: false);
      rethrow;
    }
  }

  void _applyViewPrefs(MobileViewPrefs prefs) {
    if (!ref.mounted) {
      return;
    }
    if (prefs.searchViewAsTree != state.viewAsTree) {
      state = state.copyWith(viewAsTree: prefs.searchViewAsTree);
    }
    if (prefs.searchIncludeIgnored != state.includeIgnored) {
      _changeInput(state.copyWith(includeIgnored: prefs.searchIncludeIgnored));
    }
  }

  void _changeInput(WorkspaceTextSearchState next) {
    _cancelActiveRequest();
    _generation += 1;
    state = next.copyWith(
      searching: next.hasQuery,
      error: null,
      collapsedResultNodeKeys: const <String>{},
    );
    _debounce?.cancel();
    if (!next.hasQuery) {
      state = state.copyWith(result: null, searching: false);
      return;
    }
    _debounce = Timer(_searchDebounce, () => unawaited(runNow()));
  }

  void _persist(Future<void> Function(MobileViewPrefsController) write) {
    final controller = ref.read(
      mobileViewPrefsControllerProvider(hostId).notifier,
    );
    unawaited(
      write(controller).catchError((Object error, StackTrace stackTrace) {
        // The toggle already applied locally; an older host just does not
        // share it with the desktop.
        _log.info('search view prefs not shared: $error');
      }),
    );
  }

  Future<MobileWorkspacePanelsClient?> _panels() async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    return switch (client) {
      final MobileWorkspacePanelsClient panels => panels,
      _ => null,
    };
  }

  void _cancelActiveRequest() {
    final requestId = _activeRequestId;
    if (requestId == null) {
      return;
    }
    _activeRequestId = null;
    unawaited(_cancel(requestId));
  }

  Future<void> _cancel(String requestId) async {
    try {
      await (await _panels())?.cancelWorkspaceSearch(requestId);
    } on Object {
      // Best effort: a stale generation is discarded when it answers anyway.
    }
  }
}
