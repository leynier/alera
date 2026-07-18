import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_image_row.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'workspace_git_diff_surface_rows.dart';

class WorkspaceGitDiffSurface extends ConsumerStatefulWidget {
  const WorkspaceGitDiffSurface({
    super.key,
    required this.workspace,
    required this.tab,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;

  @override
  ConsumerState<WorkspaceGitDiffSurface> createState() =>
      _WorkspaceGitDiffSurfaceState();
}

class _WorkspaceGitDiffSurfaceState
    extends ConsumerState<WorkspaceGitDiffSurface> {
  Future<GitDiffResult>? _future;
  GitDiffResult? _loadedResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WorkspaceGitDiffSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.path != widget.workspace.path ||
        oldWidget.tab.id != widget.tab.id ||
        oldWidget.tab.payload != widget.tab.payload) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filePath = widget.tab.filePath;
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.bg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _GitDiffBar(
            title: widget.tab.title,
            filePath: filePath,
            onRefresh: _load,
            onOpenFile: _canOpenFile ? () => unawaited(_openFile()) : null,
          ),
          const Divider(height: 1, color: AleraTokens.borderSubtle),
          Expanded(
            child: FutureBuilder<GitDiffResult>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _DiffMessage(message: 'Could not load diff.');
                }
                final result = snapshot.data;
                if (result == null || result.files.isEmpty) {
                  return const _DiffMessage(message: 'No diff available.');
                }
                final isCommitDiff =
                    widget.tab.gitDiffSource == WorkspaceGitDiffSource.commit;
                return _DiffFileList(
                  result: result,
                  sourcePath: _sourceControlScope.path,
                  commitOid: isCommitDiff ? widget.tab.gitDiffCommitOid : null,
                  parentOid: isCommitDiff ? widget.tab.gitDiffParentOid : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool get _canOpenFile {
    if (widget.tab.gitDiffSource == WorkspaceGitDiffSource.commit) {
      return false;
    }
    return _openableDiffFile != null;
  }

  GitDiffFile? get _openableDiffFile {
    final scope = widget.tab.gitDiffScope;
    if (widget.tab.filePath == null || scope == WorkspaceGitDiffScope.all) {
      return null;
    }
    final result = _loadedResult;
    if (result == null || result.files.isEmpty) {
      return null;
    }
    for (final file in result.files) {
      if (_isOpenableDiffFile(file)) {
        return file;
      }
    }
    return null;
  }

  bool _isOpenableDiffFile(GitDiffFile file) {
    if (file.isGitlink || file.status == GitChangeStatus.deleted) {
      return false;
    }
    if (file.status == GitChangeStatus.renamed && file.oldPath == file.path) {
      return false;
    }
    return true;
  }

  void _load() {
    final backend = ref.read(gitBackendProvider);
    final scope = widget.tab.gitDiffScope;
    final filePath = widget.tab.filePath;
    final sourceControlScope = _sourceControlScope;
    final sourceFilePath = sourceControlScope.toSourceRelativePath(filePath);
    final sourceOldPath = sourceControlScope.toSourceRelativePath(
      widget.tab.gitDiffOldPath,
    );
    final area = widget.tab.gitDiffArea;
    final nextFuture = widget.tab.gitDiffSource == WorkspaceGitDiffSource.commit
        ? _loadCommitDiff(
            backend: backend,
            sourceControlScope: sourceControlScope,
            sourceFilePath: sourceFilePath,
            sourceOldPath: sourceOldPath,
          )
        : switch (scope) {
            WorkspaceGitDiffScope.all => backend.diffAll(
              path: sourceControlScope.path,
            ),
            WorkspaceGitDiffScope.fileAll =>
              sourceFilePath == null
                  ? Future<GitDiffResult>.value(const GitDiffResult(files: []))
                  : backend.diffAll(
                      path: sourceControlScope.path,
                      filePath: sourceFilePath,
                    ),
            WorkspaceGitDiffScope.file =>
              sourceFilePath == null || area == null
                  ? Future<GitDiffResult>.value(const GitDiffResult(files: []))
                  : backend.diff(
                      path: sourceControlScope.path,
                      filePath: sourceFilePath,
                      area: area,
                    ),
            null => Future<GitDiffResult>.value(const GitDiffResult(files: [])),
          };
    setState(() {
      _loadedResult = null;
      _future = nextFuture;
    });
    unawaited(
      nextFuture.then(
        (result) {
          if (!mounted || _future != nextFuture) {
            return;
          }
          setState(() {
            _loadedResult = result;
          });
        },
        onError: (_) {
          if (!mounted || _future != nextFuture) {
            return;
          }
          setState(() {
            _loadedResult = null;
          });
        },
      ),
    );
  }

  Future<void> _openFile() {
    final file = _openableDiffFile;
    if (file == null) {
      return Future<void>.value();
    }
    return ref
        .read(workbenchControllerProvider.notifier)
        .openEditorTab(
          workspace: widget.workspace,
          relativePath: _sourceControlScope.toWorkspaceRelativePath(file.path)!,
        );
  }

  Future<GitDiffResult> _loadCommitDiff({
    required GitBackend backend,
    required WorkspaceSourceControlScope sourceControlScope,
    required String? sourceFilePath,
    required String? sourceOldPath,
  }) {
    final commitOid = widget.tab.gitDiffCommitOid;
    if (commitOid == null) {
      return Future<GitDiffResult>.value(const GitDiffResult(files: []));
    }
    return backend.commitDiff(
      path: sourceControlScope.path,
      commitOid: commitOid,
      parentOid: widget.tab.gitDiffParentOid,
      filePath: sourceFilePath,
      oldPath: sourceOldPath,
    );
  }

  WorkspaceSourceControlScope get _sourceControlScope {
    final root = normalizeSourceControlRootRelativePath(widget.tab.gitDiffRoot);
    if (root == null) {
      return WorkspaceSourceControlScope(
        workspaceId: widget.workspace.id,
        workspacePath: widget.workspace.path,
        path: widget.workspace.path,
      );
    }
    return WorkspaceSourceControlScope(
      workspaceId: widget.workspace.id,
      workspacePath: widget.workspace.path,
      path: sourceControlRootAbsolutePath(
        workspacePath: widget.workspace.path,
        relativeRoot: root,
      ),
      relativeRoot: root,
    );
  }
}

class _GitDiffBar extends StatelessWidget {
  const _GitDiffBar({
    required this.title,
    required this.filePath,
    required this.onRefresh,
    required this.onOpenFile,
  });

  final String title;
  final String? filePath;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenFile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            AleraFileIcon(
              pathOrName: filePath ?? title,
              kind: AleraFileIconKind.file,
              size: 16,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            AleraIconButton(
              tooltip: onOpenFile == null
                  ? 'File is not available in working tree'
                  : 'Open file',
              icon: AleraIcons.external,
              onPressed: onOpenFile,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Refresh',
              icon: AleraIcons.refresh,
              onPressed: onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}
