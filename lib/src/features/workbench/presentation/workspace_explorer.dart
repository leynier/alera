import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_explorer_status.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart' as tree;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

part 'workspace_explorer_actions.dart';
part 'workspace_explorer_refresh.dart';
part 'workspace_explorer_widgets.dart';

bool _isDirectoryEntry(native.WorkspaceFileEntry? entry) =>
    entry?.kind.name == 'directory';

class WorkspaceExplorer extends ConsumerStatefulWidget {
  const WorkspaceExplorer({
    super.key,
    required this.workspace,
    required this.mode,
    required this.onModeChanged,
    required this.onOpenFile,
    required this.onPathMoved,
    this.focusedSourceControlRoot,
    this.onFocusSourceControlFolder,
    this.onClearSourceControlRoot,
  });

  final Workspace workspace;
  final WorkspaceExplorerMode mode;
  final ValueChanged<WorkspaceExplorerMode> onModeChanged;
  final ValueChanged<String> onOpenFile;
  final Future<void> Function(String oldRelativePath, String newRelativePath)
  onPathMoved;
  final String? focusedSourceControlRoot;
  final Future<bool> Function(String relativePath)? onFocusSourceControlFolder;
  final VoidCallback? onClearSourceControlRoot;

  @override
  ConsumerState<WorkspaceExplorer> createState() => _WorkspaceExplorerState();
}

class _WorkspaceExplorerState extends ConsumerState<WorkspaceExplorer> {
  static const String _rootId = 'workspace-root';
  static const String _placeholderPrefix = '__alera_placeholder__:';

  late tree.DirectoryTreeController _controller;
  final Map<String, List<native.WorkspaceFileEntry>> _childrenByDirectory =
      <String, List<native.WorkspaceFileEntry>>{};
  final Map<String, native.WorkspaceFileEntry> _entryByPath =
      <String, native.WorkspaceFileEntry>{};
  final Map<String, native.WorkspaceFileEntry> _entryByNodeId =
      <String, native.WorkspaceFileEntry>{};
  native.WorkspaceExplorerTreeProjection? _projection;
  native.WorkspaceExplorerWatcherHandle? _watcherHandle;
  StreamSubscription<native.WorkspaceExplorerWatchBatch>? _watchSubscription;
  Future<void> _watchRefreshQueue = Future<void>.value();
  late final WorkspaceFileService _workspaceFiles;
  late final EditorSessionRegistry _editorSessions;
  late final WorkspaceFolderOpener _folderOpener;
  late final GitBackend _gitBackend;
  GitExplorerStatusSnapshot _gitStatusSnapshot =
      const GitExplorerStatusSnapshot.empty();
  _ExplorerClipboard? _clipboard;
  bool _loading = true;
  bool _suppressNextBackgroundMenu = false;

  @override
  void initState() {
    super.initState();
    _workspaceFiles = ref.read(workspaceFileServiceProvider);
    _editorSessions = ref.read(editorSessionRegistryProvider);
    _folderOpener = ref.read(workspaceFolderOpenerProvider);
    _gitBackend = ref.read(gitBackendProvider);
    _controller = tree.DirectoryTreeController(
      data: _buildTreeData(),
      flattenStrategy: const _AleraFlattenStrategy(),
    );
    unawaited(_bootstrapExplorer());
  }

  @override
  void didUpdateWidget(covariant WorkspaceExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.id != widget.workspace.id ||
        oldWidget.workspace.path != widget.workspace.path) {
      _loading = true;
      _clipboard = null;
      _resetExplorerProjection();
      _controller.dispose();
      _controller = tree.DirectoryTreeController(
        data: _buildTreeData(),
        flattenStrategy: const _AleraFlattenStrategy(),
      );
      unawaited(_restartExplorer());
    } else if (oldWidget.mode != widget.mode) {
      unawaited(_reloadForModeChange());
    }
  }

  @override
  void dispose() {
    unawaited(_stopNativeWatcher());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ExplorerToolbar(
          title: widget.workspace.name,
          mode: widget.mode,
          loading: _loading,
          onRefresh: () => unawaited(_reloadRoot()),
          onCollapseAll: _controller.expansions.collapseAll,
          onToggleMode: _toggleMode,
          onSaveAll: () => unawaited(_saveAllEditors()),
          onNewFile: () => unawaited(_createEntry(directory: false)),
          onNewFolder: () => unawaited(_createEntry(directory: true)),
        ),
        const Divider(height: 1, color: AleraTokens.borderSubtle),
        Expanded(
          child: _ExplorerBackgroundMenu(
            shouldSuppress: _consumeBackgroundMenuSuppression,
            onAction: _handleBackgroundAction,
            child: _loading && _controller.visibleNodes.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : tree.DirectoryTreeTheme(
                    data: const tree.DirectoryTreeThemeData(
                      rowHeight: AleraTokens.space32,
                      indent: AleraTokens.space16,
                      selectionColor: AleraTokens.surfaceElevated,
                      focusColor: AleraTokens.surfaceElevated,
                      hoverColor: AleraTokens.surface,
                      roundedCorners: false,
                    ),
                    child: tree.DirectoryTreeView(
                      controller: _controller,
                      padding: const EdgeInsets.symmetric(
                        vertical: AleraTokens.space4,
                      ),
                      expanderSize: AleraTokens.space24,
                      expanderGap: 0,
                      expanderBuilder: _buildExpander,
                      contextMenuDelegate: _ExplorerMenuDelegate(
                        fileManagerLabel: _folderOpener.fileManagerLabel,
                        canFocusSourceControlFolders:
                            widget.onFocusSourceControlFolder != null,
                        isFocusedSourceControlRoot: (node) {
                          return _entryByNodeId[node.id]?.relativePath ==
                              widget.focusedSourceControlRoot;
                        },
                        onMenuOpening: _suppressBackgroundMenuOnce,
                        onAction: _handleMenuAction,
                      ),
                      nodeBuilder: _buildNode,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpander(
    BuildContext context,
    tree.VisibleNode node,
    bool expanded,
    VoidCallback _,
  ) {
    return InkWell(
      onTap: () => unawaited(_toggleDirectory(node)),
      // InkWell defaults to adaptiveClickable, which is the basic arrow off the
      // web, so the hand cursor has to be requested explicitly here.
      mouseCursor: SystemMouseCursors.click,
      child: Icon(
        expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
        size: 16,
        color: AleraTokens.foregroundMuted,
      ),
    );
  }

  Widget _buildNode(
    BuildContext context,
    tree.VisibleNode node,
    tree.NodeVisualState state,
  ) {
    final entry = _entryByNodeId[node.id];
    final selected = _controller.selection.isSelected(node.id);
    final child = _ExplorerRow(
      name: node.name,
      entry: entry,
      expanded: state.isExpanded,
      selected: selected,
      sourceControlRoot:
          entry != null &&
          entry.relativePath == widget.focusedSourceControlRoot,
      onTap: () => unawaited(_handlePrimaryTap(node)),
    );
    if (entry == null) {
      return child;
    }
    return DragTarget<_ExplorerDragData>(
      onWillAcceptWithDetails: (details) =>
          _canDrop(details.data, entry.relativePath),
      onAcceptWithDetails: (details) =>
          unawaited(_moveEntry(details.data.relativePath, entry.relativePath)),
      builder: (context, _, _) => LongPressDraggable<_ExplorerDragData>(
        data: _ExplorerDragData(relativePath: entry.relativePath),
        feedback: Material(color: Colors.transparent, child: child),
        childWhenDragging: Opacity(opacity: 0.45, child: child),
        child: child,
      ),
    );
  }

  Future<void> _reloadRoot() async {
    setState(() => _loading = true);
    try {
      _resetExplorerProjection();
      await _refreshGitStatusSnapshot();
      await _syncWatchedDirectories();
      await _loadDirectory('');
      if (!mounted) {
        return;
      }
      _rebuildTree();
    } catch (error) {
      if (mounted) {
        _rebuildTree(tryPreserveState: false);
      }
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _reloadForModeChange() async {
    final loadedDirectories =
        _childrenByDirectory.keys
            .where((relativePath) => relativePath.isNotEmpty)
            .toList(growable: false)
          ..sort(_compareDirectoryDepth);
    setState(() => _loading = true);
    try {
      _resetExplorerProjection();
      await _refreshGitStatusSnapshot();
      await _syncWatchedDirectories();
      await _loadDirectory('');
      for (final relativePath in loadedDirectories) {
        if (!mounted) {
          return;
        }
        if (!_isDirectoryEntry(_entryByPath[relativePath])) {
          continue;
        }
        await _loadDirectory(relativePath);
      }
      if (!mounted) {
        return;
      }
      _rebuildTree();
    } catch (error) {
      if (mounted) {
        _rebuildTree(tryPreserveState: false);
      }
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadDirectory(String relativePath) async {
    final rawChildren = await _workspaceFiles.listChildren(
      workspacePath: widget.workspace.path,
      relativePath: relativePath,
      hideIgnored: widget.mode == WorkspaceExplorerMode.hideIgnored,
    );
    final children = _workspaceFiles.applyGitStatusSnapshot(
      rawChildren,
      _gitStatusSnapshot,
    );
    if (!mounted) {
      return;
    }
    await _replaceDirectoryChildren(relativePath, children);
  }

  Future<void> _refreshGitStatusSnapshot() async {
    try {
      _gitStatusSnapshot = await _gitBackend.explorerStatusSnapshot(
        widget.workspace.path,
      );
    } catch (_) {
      _gitStatusSnapshot = const GitExplorerStatusSnapshot.empty();
    }
  }

  void _rebuildTree({bool tryPreserveState = true}) {
    if (!mounted) {
      return;
    }
    final next = _buildTreeData();
    _controller.rebuild(next, tryPreserveState: tryPreserveState);
  }

  int _compareDirectoryDepth(String left, String right) {
    final depthComparison = _directoryDepth(
      left,
    ).compareTo(_directoryDepth(right));
    if (depthComparison != 0) {
      return depthComparison;
    }
    return left.compareTo(right);
  }

  int _directoryDepth(String relativePath) {
    if (relativePath.isEmpty) {
      return 0;
    }
    return relativePath.split('/').length;
  }

  tree.TreeData _buildTreeData() {
    final projection = _projection;
    final nodes = projection == null
        ? <String, tree.TreeNode>{
            _rootId: tree.TreeNode(
              id: _rootId,
              name: widget.workspace.name,
              type: tree.NodeType.root,
              parentId: '',
              virtualPath: '/',
              sourcePath: widget.workspace.path,
              isExpanded: true,
            ),
          }
        : <String, tree.TreeNode>{
            for (final node in projection.nodes)
              node.id: tree.TreeNode(
                id: node.id,
                name: node.name,
                type: _treeNodeType(node.kind),
                parentId: node.parentId,
                virtualPath: node.virtualPath,
                sourcePath: node.sourcePath,
                entryId: node.entryId,
                childIds: node.childIds,
                isExpanded: node.isExpanded,
                isVirtual: node.isVirtual,
              ),
          };
    return tree.TreeData(
      nodes: Map<String, tree.TreeNode>.unmodifiable(nodes),
      rootId: _rootId,
      visibleRootId: _rootId,
      omitContainerRowAtRoot: true,
    );
  }

  Future<void> _handlePrimaryTap(tree.VisibleNode node) async {
    _select(node);
    final entry = _entryByNodeId[node.id];
    if (_isDirectoryEntry(entry)) {
      await _toggleDirectory(node);
      return;
    }
    if (entry != null) {
      widget.onOpenFile(entry.relativePath);
    }
  }

  Future<void> _toggleDirectory(tree.VisibleNode node) async {
    final entry = _entryByNodeId[node.id];
    if (!_isDirectoryEntry(entry)) {
      if (!mounted) {
        return;
      }
      _controller.toggle(node.id);
      return;
    }
    final directory = entry!;
    if (!_childrenByDirectory.containsKey(directory.relativePath)) {
      await _loadDirectory(directory.relativePath);
      if (!mounted) {
        return;
      }
      _rebuildTree();
    }
    _controller.toggle(node.id);
  }

  void _select(tree.VisibleNode node) {
    _controller.selection.selectOnly(node.id);
  }

  void _setClipboard(_ExplorerClipboard? clipboard) {
    if (!mounted) {
      return;
    }
    setState(() => _clipboard = clipboard);
  }

  void _suppressBackgroundMenuOnce() {
    _suppressNextBackgroundMenu = true;
  }

  bool _consumeBackgroundMenuSuppression() {
    if (!_suppressNextBackgroundMenu) {
      return false;
    }
    _suppressNextBackgroundMenu = false;
    return true;
  }

  tree.NodeType _treeNodeType(native.WorkspaceExplorerTreeNodeKind kind) {
    return switch (kind) {
      native.WorkspaceExplorerTreeNodeKind.root => tree.NodeType.root,
      native.WorkspaceExplorerTreeNodeKind.folder => tree.NodeType.folder,
      native.WorkspaceExplorerTreeNodeKind.file => tree.NodeType.file,
    };
  }
}

class _AleraFlattenStrategy extends tree.FlattenStrategy {
  const _AleraFlattenStrategy();

  static const tree.DefaultFlattenStrategy _delegate =
      tree.DefaultFlattenStrategy();

  @override
  List<tree.VisibleNode> flatten({
    required tree.TreeData data,
    required Set<String> expandedIds,
    String? filterQuery,
  }) {
    return _delegate
        .flatten(data: data, expandedIds: expandedIds, filterQuery: filterQuery)
        .where(
          (node) =>
              !node.id.startsWith(_WorkspaceExplorerState._placeholderPrefix),
        )
        .toList(growable: false);
  }
}
