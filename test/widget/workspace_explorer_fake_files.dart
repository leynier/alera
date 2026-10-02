part of 'workspace_explorer_test.dart';

class _FakeWorkspaceFileService({
  final Completer<void>? createGate,
  final Completer<void>? stopGate,
}) extends WorkspaceFileService {
  final StreamController<native.WorkspaceExplorerWatchBatch> _watchController =
      StreamController<native.WorkspaceExplorerWatchBatch>.broadcast(
        sync: true,
      );
  final Map<String, List<native.WorkspaceFileEntry>> childrenByDirectory =
      <String, List<native.WorkspaceFileEntry>>{};
  final Map<String, Map<String, List<native.WorkspaceFileEntry>>>
  childrenByWorkspacePath =
      <String, Map<String, List<native.WorkspaceFileEntry>>>{};
  final Map<String, List<native.WorkspaceFileEntry>>
  showAllChildrenByDirectory = <String, List<native.WorkspaceFileEntry>>{};
  final Map<String, Map<String, List<native.WorkspaceFileEntry>>>
  showAllChildrenByWorkspacePath =
      <String, Map<String, List<native.WorkspaceFileEntry>>>{};
  final Set<_ListChildrenCall> failingListChildrenCalls = <_ListChildrenCall>{};
  final List<String> createdFiles = <String>[];
  final List<String> copiedFiles = <String>[];
  final List<_ListChildrenCall> listChildrenCalls = <_ListChildrenCall>[];
  final List<List<String>> watchedPathUpdates = <List<String>>[];
  final Map<String, String> writtenFiles = <String, String>{};
  final Map<String, Completer<void>> listChildrenGatesByDirectory =
      <String, Completer<void>>{};
  Completer<void>? listChildrenGate;
  bool _listChildrenGateUsed = false;
  final List<Completer<void>> projectionGates = <Completer<void>>[];
  final Map<String, Completer<void>> projectionGatesByDirectory =
      <String, Completer<void>>{};
  final List<String> projectionCallDirectories = <String>[];
  int _projectionCallCount = 0;
  final List<Completer<void>> watcherUpdateGates = <Completer<void>>[];
  int watcherUpdateCallCount = 0;
  int startWatcherCalls = 0;
  int stopWatcherCalls = 0;
  bool startCalledWhileStopPending = false;
  bool _stopPending = false;

  void emitWatchBatch(List<String> directoryRelativePaths) {
    _watchController.add(
      native.WorkspaceExplorerWatchBatch(
        directoryRelativePaths: directoryRelativePaths,
        changedRelativePaths: const <String>[],
        coalescedEventCount: 0,
      ),
    );
  }

  @override
  Future<List<native.WorkspaceFileEntry>> listChildren({
    required String workspacePath,
    required String relativePath,
    required bool hideIgnored,
  }) async {
    final call = _ListChildrenCall(
      relativePath: relativePath,
      hideIgnored: hideIgnored,
    );
    listChildrenCalls.add(call);
    if (failingListChildrenCalls.contains(call)) {
      throw StateError('Failed to list $relativePath');
    }
    final directoryGate = listChildrenGatesByDirectory[relativePath];
    if (directoryGate != null) {
      await directoryGate.future;
    }
    final gate = listChildrenGate;
    if (gate != null && !_listChildrenGateUsed) {
      _listChildrenGateUsed = true;
      await gate.future;
    }
    final workspaceChildren = childrenByWorkspacePath[workspacePath];
    final workspaceShowAllChildren =
        showAllChildrenByWorkspacePath[workspacePath];
    final workspaceModeChildren = hideIgnored
        ? workspaceChildren
        : workspaceShowAllChildren;
    return workspaceModeChildren?[relativePath] ??
        workspaceChildren?[relativePath] ??
        (hideIgnored
            ? childrenByDirectory[relativePath]
            : showAllChildrenByDirectory[relativePath]) ??
        childrenByDirectory[relativePath] ??
        const <native.WorkspaceFileEntry>[];
  }

  @override
  Future<native.WorkspaceExplorerTreeProjection> projectExplorerTree({
    required String workspaceName,
    required String workspacePath,
    required List<native.WorkspaceExplorerDirectoryChildren> directories,
    native.WorkspaceExplorerDirectoryChildren? replacement,
  }) async {
    final projectionCall = _projectionCallCount;
    _projectionCallCount += 1;
    final replacementPath = replacement?.relativePath;
    if (replacementPath != null) {
      projectionCallDirectories.add(replacementPath);
    }
    final directoryGate = replacementPath == null
        ? null
        : projectionGatesByDirectory[replacementPath];
    if (directoryGate != null) {
      await directoryGate.future;
    }
    if (projectionCall < projectionGates.length) {
      await projectionGates[projectionCall].future;
    }
    return _projectExplorerTree(
      workspaceName: workspaceName,
      workspacePath: workspacePath,
      directories: directories,
      replacement: replacement,
    );
  }

  @override
  Future<native.WorkspaceExplorerWatcherHandle> startExplorerWatcher({
    required String workspacePath,
  }) async {
    startWatcherCalls += 1;
    if (_stopPending) {
      startCalledWhileStopPending = true;
    }
    return native.WorkspaceExplorerWatcherHandle(
      id: 'watcher-$startWatcherCalls',
    );
  }

  @override
  Future<void> updateExplorerWatcher({
    required native.WorkspaceExplorerWatcherHandle handle,
    required List<String> watchedRelativePaths,
  }) async {
    final updateCall = watcherUpdateCallCount;
    watcherUpdateCallCount += 1;
    if (updateCall < watcherUpdateGates.length) {
      await watcherUpdateGates[updateCall].future;
    }
    watchedPathUpdates.add(watchedRelativePaths);
  }

  @override
  Stream<native.WorkspaceExplorerWatchBatch> watchExplorerEvents({
    required native.WorkspaceExplorerWatcherHandle handle,
  }) {
    return _watchController.stream;
  }

  @override
  Future<void> stopExplorerWatcher({
    required native.WorkspaceExplorerWatcherHandle handle,
  }) async {
    stopWatcherCalls += 1;
    _stopPending = true;
    try {
      await stopGate?.future;
    } finally {
      _stopPending = false;
    }
  }

  @override
  Future<native.WorkspaceFileEntry> createFile({
    required String workspacePath,
    required String parentRelativePath,
    required String name,
  }) async {
    createdFiles.add(name);
    await createGate?.future;
    final relativePath = parentRelativePath.isEmpty
        ? name
        : '$parentRelativePath/$name';
    final entry = _file(relativePath);
    childrenByDirectory[parentRelativePath] = <native.WorkspaceFileEntry>[
      ...?childrenByDirectory[parentRelativePath],
      entry,
    ];
    return entry;
  }

  @override
  Future<native.WorkspaceEditorTextFile> writeEditorTextFile({
    required String workspacePath,
    required String relativePath,
    required String currentDisplayContent,
    required String? originalRawContent,
    required String? originalDisplayContent,
    required String? expectedContentToken,
    required bool overwriteIfChanged,
    required int tabSize,
  }) async {
    writtenFiles[relativePath] = currentDisplayContent;
    return native.WorkspaceEditorTextFile(
      rawContent: currentDisplayContent,
      displayContent: currentDisplayContent,
      contentToken: '$relativePath-saved-token',
      modifiedMillis: 1,
      size: .from(currentDisplayContent.length),
    );
  }

  @override
  Future<native.WorkspaceFileEntry> copyEntry({
    required String workspacePath,
    required String relativePath,
    required String targetParentRelativePath,
  }) async {
    copiedFiles.add('$relativePath->$targetParentRelativePath');
    final copyName = '${relativePath.split('/').last} copy';
    final copyPath = targetParentRelativePath.isEmpty
        ? copyName
        : '$targetParentRelativePath/$copyName';
    final entry = _file(copyPath);
    childrenByDirectory[targetParentRelativePath] = <native.WorkspaceFileEntry>[
      ...?childrenByDirectory[targetParentRelativePath],
      entry,
    ];
    return entry;
  }
}

class const _ListChildrenCall({
  required final String relativePath,
  required final bool hideIgnored,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ListChildrenCall &&
          other.relativePath == relativePath &&
          other.hideIgnored == hideIgnored;

  @override
  int get hashCode => Object.hash(relativePath, hideIgnored);
}

native.WorkspaceExplorerTreeProjection _projectExplorerTree({
  required String workspaceName,
  required String workspacePath,
  required List<native.WorkspaceExplorerDirectoryChildren> directories,
  native.WorkspaceExplorerDirectoryChildren? replacement,
}) {
  final directoriesByPath = <String, List<native.WorkspaceFileEntry>>{
    for (final directory in directories)
      directory.relativePath: directory.children,
  };
  if (replacement != null) {
    final previous = directoriesByPath[replacement.relativePath];
    if (previous != null) {
      final nextPaths = replacement.children
          .map((entry) => entry.relativePath)
          .toSet();
      for (final entry in previous) {
        if (!nextPaths.contains(entry.relativePath)) {
          _removeProjectedSubtree(directoriesByPath, entry.relativePath);
        }
      }
    }
    directoriesByPath[replacement.relativePath] = replacement.children;
  }
  final knownPaths = directoriesByPath.values
      .expand((children) => children.map((entry) => entry.relativePath))
      .toSet();
  directoriesByPath.removeWhere(
    (path, _) => path.isNotEmpty && !knownPaths.contains(path),
  );

  final nodes = <String, native.WorkspaceExplorerTreeNode>{
    'workspace-root': native.WorkspaceExplorerTreeNode(
      id: 'workspace-root',
      name: workspaceName,
      kind: native.WorkspaceExplorerTreeNodeKind.root,
      parentId: '',
      virtualPath: '/',
      sourcePath: workspacePath,
      childIds: <String>[],
      isExpanded: true,
      isVirtual: false,
    ),
  };
  final entryBindings = <native.WorkspaceExplorerEntryBinding>[];
  for (final entries in directoriesByPath.values) {
    for (final entry in entries) {
      _addProjectedEntry(nodes, entryBindings, entry);
      if (entry.kind == native.WorkspaceFileKind.directory &&
          entry.hasChildrenHint &&
          !directoriesByPath.containsKey(entry.relativePath)) {
        _addProjectedPlaceholder(nodes, entry.relativePath);
      }
    }
  }

  return native.WorkspaceExplorerTreeProjection(
    directories: directoriesByPath.entries
        .map(
          (entry) => native.WorkspaceExplorerDirectoryChildren(
            relativePath: entry.key,
            children: entry.value,
          ),
        )
        .toList(growable: false),
    nodes: nodes.values.toList(growable: false),
    entryBindings: entryBindings,
  );
}

void _removeProjectedSubtree(
  Map<String, List<native.WorkspaceFileEntry>> directoriesByPath,
  String relativePath,
) {
  final prefix = '$relativePath/';
  directoriesByPath.removeWhere(
    (path, _) => path == relativePath || path.startsWith(prefix),
  );
  for (final entry in directoriesByPath.entries.toList()) {
    directoriesByPath[entry.key] = entry.value
        .where(
          (child) =>
              child.relativePath != relativePath &&
              !child.relativePath.startsWith(prefix),
        )
        .toList(growable: false);
  }
}

void _addProjectedEntry(
  Map<String, native.WorkspaceExplorerTreeNode> nodes,
  List<native.WorkspaceExplorerEntryBinding> entryBindings,
  native.WorkspaceFileEntry entry,
) {
  final parts = entry.relativePath.split('/');
  var parentId = 'workspace-root';
  var currentPath = '';
  for (var index = 0; index < parts.length; index += 1) {
    final part = parts[index];
    currentPath = currentPath.isEmpty ? part : '$currentPath/$part';
    final isLeaf = index == parts.length - 1;
    final nodeId = 'path:$currentPath';
    if (!nodes.containsKey(nodeId)) {
      nodes[nodeId] = native.WorkspaceExplorerTreeNode(
        id: nodeId,
        name: part,
        kind: isLeaf && entry.kind != native.WorkspaceFileKind.directory
            ? native.WorkspaceExplorerTreeNodeKind.file
            : native.WorkspaceExplorerTreeNodeKind.folder,
        parentId: parentId,
        virtualPath: '/$currentPath',
        sourcePath: currentPath,
        entryId: isLeaf ? entry.relativePath : null,
        childIds: <String>[],
        isExpanded: false,
        isVirtual: false,
      );
      _appendProjectedChild(nodes, parentId, nodeId);
    }
    if (isLeaf) {
      entryBindings.add(
        native.WorkspaceExplorerEntryBinding(
          nodeId: nodeId,
          relativePath: entry.relativePath,
        ),
      );
    }
    parentId = nodeId;
  }
}

void _addProjectedPlaceholder(
  Map<String, native.WorkspaceExplorerTreeNode> nodes,
  String parentPath,
) {
  final parentId = 'path:$parentPath';
  final nodeId = '__alera_placeholder__:$parentPath';
  if (!nodes.containsKey(parentId) || nodes.containsKey(nodeId)) {
    return;
  }
  nodes[nodeId] = native.WorkspaceExplorerTreeNode(
    id: nodeId,
    name: '',
    kind: native.WorkspaceExplorerTreeNodeKind.file,
    parentId: parentId,
    virtualPath: '/$parentPath/.alera-placeholder',
    sourcePath: '',
    childIds: <String>[],
    isExpanded: false,
    isVirtual: true,
  );
  _appendProjectedChild(nodes, parentId, nodeId);
}

void _appendProjectedChild(
  Map<String, native.WorkspaceExplorerTreeNode> nodes,
  String parentId,
  String childId,
) {
  final parent = nodes[parentId];
  if (parent != null && !parent.childIds.contains(childId)) {
    parent.childIds.add(childId);
  }
}
