part of 'workspace_explorer_test.dart';

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
