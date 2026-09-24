part of 'workspace_explorer_test.dart';

class _FakeWorkspaceFileService({
  final Completer<void>? createGate,
  final Completer<void>? stopGate,
}) extends WorkspaceFileService {
  final StreamController<native.WorkspaceExplorerWatchBatch> _watchController =
      StreamController<native.WorkspaceExplorerWatchBatch>.broadcast();
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
    return const native.WorkspaceExplorerWatcherHandle(id: 'watcher-1');
  }

  @override
  Future<void> updateExplorerWatcher({
    required native.WorkspaceExplorerWatcherHandle handle,
    required List<String> watchedRelativePaths,
  }) async {
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
    await stopGate?.future;
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

class _FakeWorkspaceFolderOpener() extends WorkspaceFolderOpener {
  this : super(processRunner: _NoopProcessRunner(), platform: .macos);

  final List<String> revealedPaths = <String>[];

  @override
  Future<WorkspaceFolderOpenResult> reveal(String path) async {
    revealedPaths.add(path);
    return const WorkspaceFolderOpenResult.success();
  }
}

class _NoopProcessRunner implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) {
    throw UnimplementedError();
  }
}

Workspace _workspace({
  String id = 'workspace-1',
  String name = 'alera',
  String path = '/repo/alera',
}) {
  final now = DateTime.utc(2026);
  return Workspace(
    id: id,
    projectId: 'project-1',
    name: name,
    path: path,
    createdAt: now,
    updatedAt: now,
    kind: .main,
    status: .active,
  );
}

native.WorkspaceFileEntry _file(
  String relativePath, {
  native.WorkspaceFileGitStatus? gitStatus,
}) {
  return _entry(
    relativePath: relativePath,
    kind: native.WorkspaceFileKind.file,
    hasChildrenHint: false,
    gitStatus: gitStatus,
  );
}

native.WorkspaceFileEntry _directory(
  String relativePath, {
  required bool hasChildrenHint,
  native.WorkspaceFileGitStatus? gitStatus,
}) {
  return _entry(
    relativePath: relativePath,
    kind: native.WorkspaceFileKind.directory,
    hasChildrenHint: hasChildrenHint,
    gitStatus: gitStatus,
  );
}

native.WorkspaceFileEntry _entry({
  required String relativePath,
  required native.WorkspaceFileKind kind,
  required bool hasChildrenHint,
  native.WorkspaceFileGitStatus? gitStatus,
}) {
  return native.WorkspaceFileEntry(
    relativePath: relativePath,
    name: relativePath.split('/').last,
    kind: kind,
    size: .zero,
    modifiedMillis: 0,
    contentToken: '$relativePath-token',
    isIgnored: false,
    isHidden: false,
    isSymlink: false,
    isProtected: false,
    hasChildrenHint: hasChildrenHint,
    gitStatus: gitStatus,
  );
}
