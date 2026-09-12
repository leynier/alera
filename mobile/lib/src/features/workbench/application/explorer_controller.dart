import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
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
}) {
  bool get isEmpty => rows.isEmpty && error == null;
}

@riverpod
class ExplorerController extends _$ExplorerController {
  final Set<String> _expanded = <String>{};
  final Map<String, List<MobileExplorerEntry>> _children =
      <String, List<MobileExplorerEntry>>{};

  @override
  Future<ExplorerViewState> build(String hostId, String workspaceId) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    if (client case final MobileWorkspacePanelsClient panels
        when panels.supportsExplorer) {
      try {
        _children[''] = await panels.listExplorerChildren(
          workspaceId: workspaceId,
        );
      } on Object catch (error) {
        return ExplorerViewState(error: error);
      }
      return ExplorerViewState(rows: _visibleRows());
    }
    return const ExplorerViewState(
      error: 'Update the paired Alera runtime to browse files.',
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
      state = AsyncData(ExplorerViewState(rows: _visibleRows()));
      return;
    }
    _expanded.add(entry.relativePath);
    if (_children.containsKey(entry.relativePath)) {
      state = AsyncData(ExplorerViewState(rows: _visibleRows()));
      return;
    }
    state = AsyncData(
      ExplorerViewState(rows: _visibleRows(loadingPath: entry.relativePath)),
    );
    final client = await ref.read(workspaceClientProvider(hostId).future);
    if (client case final MobileWorkspacePanelsClient panels) {
      try {
        _children[entry.relativePath] = await panels.listExplorerChildren(
          workspaceId: workspaceId,
          relativePath: entry.relativePath,
        );
        state = AsyncData(ExplorerViewState(rows: _visibleRows()));
      } on Object catch (error) {
        _expanded.remove(entry.relativePath);
        state = AsyncData(
          ExplorerViewState(rows: _visibleRows(), error: error),
        );
      }
      return;
    }
  }

  /// Rebuilds in place: Riverpod carries the last rows through the loading
  /// and error states, so the panel keeps its tree on screen.
  Future<void> reload() async {
    _expanded.clear();
    _children.clear();
    ref.invalidateSelf();
    try {
      await future;
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'could not refresh the explorer for $workspaceId',
        error,
        stackTrace,
      );
    }
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
