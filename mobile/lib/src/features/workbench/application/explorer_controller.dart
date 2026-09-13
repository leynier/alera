import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/explorer_preferences_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'explorer_controller.g.dart';

final Logger _logger = Logger('ExplorerController');

class const ExplorerRow({
  required final MobileExplorerEntry entry,
  required final int depth,
  final bool expanded = false,
  final bool loadingChildren = false,
});

class const ExplorerViewState({
  final List<ExplorerRow> rows = const <ExplorerRow>[],
  final Object? error,
  final bool hideIgnored = true,
  final bool refreshing = false,
}) {
  bool get isEmpty => rows.isEmpty && error == null;

  bool get hasExpandedFolders => rows.any((row) => row.expanded);
}

/// Outcome of asking to use a folder as the Source Control root.
enum SourceControlRootResult { applied, notRepository, unsupported }

@riverpod
class ExplorerController extends _$ExplorerController {
  final Set<String> _expanded = <String>{};
  final Map<String, List<MobileExplorerEntry>> _children =
      <String, List<MobileExplorerEntry>>{};
  bool _hideIgnored = true;

  @override
  Future<ExplorerViewState> build(String hostId, String workspaceId) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    final preferences = await ref.read(
      explorerPreferencesControllerProvider(hostId, workspaceId).future,
    );
    _hideIgnored = preferences.hideIgnored;
    if (client case final MobileWorkspacePanelsClient panels
        when panels.supportsExplorer) {
      try {
        _children[''] = await panels.listExplorerChildren(
          workspaceId: workspaceId,
          hideIgnored: _hideIgnored,
        );
      } on Object catch (error) {
        return ExplorerViewState(error: error, hideIgnored: _hideIgnored);
      }
      return _view();
    }
    return ExplorerViewState(
      error: 'Update the paired Alera runtime to browse files.',
      hideIgnored: _hideIgnored,
    );
  }

  Future<void> toggle(MobileExplorerEntry entry) async {
    if (!entry.isDirectory) {
      return;
    }
    final current = state.value;
    if (current == null) {
      return;
    }
    if (_expanded.contains(entry.relativePath)) {
      _expanded.remove(entry.relativePath);
      state = AsyncData(_view());
      return;
    }
    _expanded.add(entry.relativePath);
    if (_children.containsKey(entry.relativePath)) {
      state = AsyncData(_view());
      return;
    }
    state = AsyncData(_view(loadingPath: entry.relativePath));
    final client = await ref.read(workspaceClientProvider(hostId).future);
    if (client case final MobileWorkspacePanelsClient panels) {
      try {
        _children[entry.relativePath] = await panels.listExplorerChildren(
          workspaceId: workspaceId,
          relativePath: entry.relativePath,
          hideIgnored: _hideIgnored,
        );
        state = AsyncData(_view());
      } on Object catch (error) {
        _expanded.remove(entry.relativePath);
        state = AsyncData(_view(error: error));
      }
      return;
    }
  }

  void collapseAll() {
    if (_expanded.isEmpty) {
      return;
    }
    _expanded.clear();
    state = AsyncData(_view());
  }

  Future<void> setHideIgnored(bool value) async {
    if (value == _hideIgnored) {
      return;
    }
    _hideIgnored = value;
    await ref
        .read(
          explorerPreferencesControllerProvider(hostId, workspaceId).notifier,
        )
        .setHideIgnored(value);
    await refresh();
  }

  /// Re-reads the root and every folder still open, keeping them open. Folders
  /// that disappeared, or that the ignore filter now hides, simply close.
  Future<void> refresh() async {
    final current = state.value;
    if (current == null || current.rows.isEmpty && current.error != null) {
      await reload();
      return;
    }
    if (current.refreshing) {
      return;
    }
    state = AsyncData(_view(refreshing: true));
    final client = await _panelsClient();
    if (client == null) {
      state = AsyncData(_view());
      return;
    }
    final next = <String, List<MobileExplorerEntry>>{};
    try {
      next[''] = await client.listExplorerChildren(
        workspaceId: workspaceId,
        hideIgnored: _hideIgnored,
      );
      var level = _expandedChildrenOf(next, '');
      while (level.isNotEmpty) {
        final listed = await Future.wait(<Future<List<MobileExplorerEntry>?>>[
          for (final path in level) _listOrNull(client, path),
        ]);
        final nextLevel = <String>[];
        for (var index = 0; index < level.length; index += 1) {
          final entries = listed[index];
          if (entries == null) {
            continue;
          }
          next[level[index]] = entries;
          nextLevel.addAll(_expandedChildrenOf(next, level[index]));
        }
        level = nextLevel;
      }
    } on Object catch (error, stackTrace) {
      _logger.warning('could not refresh explorer', error, stackTrace);
      state = AsyncData(_view(error: error));
      return;
    }
    _children
      ..clear()
      ..addAll(next);
    _expanded.removeWhere((path) => !next.containsKey(path));
    state = AsyncData(_view());
  }

  Future<void> reload() async {
    _expanded.clear();
    _children.clear();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(hostId, workspaceId));
  }

  /// Validates [relativePath] against the host before saving it, so a folder
  /// that is not its own repository never becomes the Source Control root.
  Future<SourceControlRootResult> useAsSourceControlRoot(
    String relativePath,
  ) async {
    final client = await _panelsClient();
    if (client == null || !client.supportsSourceControlRoot) {
      return SourceControlRootResult.unsupported;
    }
    final snapshot = await client.gitStatus(
      workspaceId,
      relativeRoot: relativePath,
    );
    if (!snapshot.isRepository) {
      return SourceControlRootResult.notRepository;
    }
    await ref
        .read(
          explorerPreferencesControllerProvider(hostId, workspaceId).notifier,
        )
        .setSourceControlRoot(relativePath);
    return SourceControlRootResult.applied;
  }

  Future<void> clearSourceControlRoot() {
    return ref
        .read(
          explorerPreferencesControllerProvider(hostId, workspaceId).notifier,
        )
        .setSourceControlRoot(null);
  }

  Future<MobileWorkspacePanelsClient?> _panelsClient() async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    return client is MobileWorkspacePanelsClient
        ? client as MobileWorkspacePanelsClient
        : null;
  }

  Future<List<MobileExplorerEntry>?> _listOrNull(
    MobileWorkspacePanelsClient client,
    String relativePath,
  ) async {
    try {
      return await client.listExplorerChildren(
        workspaceId: workspaceId,
        relativePath: relativePath,
        hideIgnored: _hideIgnored,
      );
    } on Object catch (error, stackTrace) {
      _logger.info(
        'closing folder that could not be listed',
        error,
        stackTrace,
      );
      return null;
    }
  }

  List<String> _expandedChildrenOf(
    Map<String, List<MobileExplorerEntry>> listing,
    String parent,
  ) {
    return <String>[
      for (final entry in listing[parent] ?? const <MobileExplorerEntry>[])
        if (entry.isDirectory && _expanded.contains(entry.relativePath))
          entry.relativePath,
    ];
  }

  ExplorerViewState _view({
    String? loadingPath,
    Object? error,
    bool refreshing = false,
  }) {
    return ExplorerViewState(
      rows: _visibleRows(loadingPath: loadingPath),
      error: error,
      hideIgnored: _hideIgnored,
      refreshing: refreshing,
    );
  }

  List<ExplorerRow> _visibleRows({String? loadingPath}) {
    final rows = <ExplorerRow>[];
    void walk(String parent, int depth) {
      for (final entry in _children[parent] ?? const <MobileExplorerEntry>[]) {
        final expanded = _expanded.contains(entry.relativePath);
        rows.add(
          ExplorerRow(
            entry: entry,
            depth: depth,
            expanded: expanded,
            loadingChildren: loadingPath == entry.relativePath,
          ),
        );
        if (expanded) {
          walk(entry.relativePath, depth + 1);
        }
      }
    }

    walk('', 0);
    return rows;
  }
}
