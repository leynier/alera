import 'dart:async';
import 'dart:typed_data';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_errors.dart';
import 'package:alera/src/features/reading_diff/application/reading_diff_providers.dart';
import 'package:alera/src/features/reading_diff/application/reading_diff_generation_progress.dart';
import 'package:alera/src/features/reading_diff/domain/reading_diff_models.dart';
import 'package:alera/src/features/reading_diff/presentation/reading_diff_confirmation_dialog.dart';
import 'package:alera/src/features/reading_diff/presentation/reading_diff_failure_view.dart';
import 'package:alera/src/features/reading_diff/presentation/reading_diff_generation_progress_view.dart';
import 'package:alera/src/features/reading_diff/presentation/reading_diff_view.dart';
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
part 'workspace_git_diff_surface_bar.dart';

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
  ReadingDiffResult? _readingDiffResult;
  Uint8List? _readingDiffOriginalSnapshot;
  bool _showReadingDiff = false;
  bool _readingDiffBusy = false;
  ReadingDiffGenerationProgress? _readingDiffProgress;
  String? _readingDiffError;
  String? _readingDiffAgentLabel;
  String? _readingDiffModel;
  ReadingDiffRequest? _activeReadingDiffRequest;
  int _readingDiffGeneration = 0;

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
        _diffSelectionChanged(oldWidget.tab, widget.tab)) {
      _load();
    }
  }

  bool _diffSelectionChanged(
    WorkspaceTabRecord previous,
    WorkspaceTabRecord current,
  ) {
    return previous.kind != current.kind ||
        previous.filePath != current.filePath ||
        previous.gitDiffOldPath != current.gitDiffOldPath ||
        previous.gitDiffRoot != current.gitDiffRoot ||
        previous.gitDiffScope != current.gitDiffScope ||
        previous.gitDiffArea != current.gitDiffArea ||
        previous.gitDiffSource != current.gitDiffSource ||
        previous.gitDiffCommitOid != current.gitDiffCommitOid ||
        previous.gitDiffParentOid != current.gitDiffParentOid ||
        previous.gitDiffCompareRef != current.gitDiffCompareRef ||
        previous.gitDiffPullRequestNumber != current.gitDiffPullRequestNumber ||
        previous.gitDiffHostedReviewRetentionId !=
            current.gitDiffHostedReviewRetentionId;
  }

  @override
  void dispose() {
    final activeRequest = _activeReadingDiffRequest;
    if (activeRequest != null) {
      ref.read(readingDiffServiceProvider).cancel(activeRequest);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filePath = widget.tab.filePath;
    final aiTextEnabled = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.aiTextGeneration.enabled,
      ),
    );
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
            aiTextEnabled: aiTextEnabled,
            readingDiffReady: _readingDiffResult != null,
            showingReadingDiff: _showReadingDiff,
            readingDiffBusy: _readingDiffBusy,
            onGenerateReadingDiff: _loadedResult?.files.isNotEmpty == true
                ? () => unawaited(_generateReadingDiff())
                : null,
            onRegenerateReadingDiff: _loadedResult?.files.isNotEmpty == true
                ? () => unawaited(_generateReadingDiff(ignoreCache: true))
                : null,
            onCancelReadingDiff: _cancelReadingDiff,
            onToggleReadingDiff: _readingDiffResult == null
                ? null
                : () => setState(() {
                    _showReadingDiff = !_showReadingDiff;
                  }),
          ),
          const Divider(height: 1, color: AleraTokens.borderSubtle),
          if (_readingDiffProgress case final progress?) ...<Widget>[
            ReadingDiffGenerationProgressView(
              progress: progress,
              agentLabel: _readingDiffAgentLabel,
              model: _readingDiffModel,
            ),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
          ],
          if (_readingDiffError case final error?) ...<Widget>[
            ReadingDiffFailureView(
              message: error,
              onDismiss: () => setState(() => _readingDiffError = null),
            ),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
          ],
          Expanded(
            child: _showReadingDiff && _readingDiffResult != null
                ? ReadingDiffView(result: _readingDiffResult!)
                : _readingDiffOriginalSnapshot != null
                ? ReadingDiffText(
                    diff: _readingDiffOriginalSnapshot!,
                    failureLabel: 'original diff snapshot',
                  )
                : FutureBuilder<GitDiffResult>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return const _DiffMessage(
                          message: 'Could not load diff.',
                        );
                      }
                      final result = snapshot.data;
                      if (result == null || result.files.isEmpty) {
                        return const _DiffMessage(
                          message: 'No diff available.',
                        );
                      }
                      final isCommitDiff = _isCommitBackedDiff;
                      return _DiffFileList(
                        result: result,
                        sourcePath: _sourceControlScope.path,
                        sourceLabel:
                            widget.tab.gitDiffSource ==
                                WorkspaceGitDiffSource.pullRequest
                            ? 'Pull Request'
                            : null,
                        commitOid: isCommitDiff
                            ? widget.tab.gitDiffCommitOid
                            : null,
                        parentOid: isCommitDiff
                            ? widget.tab.gitDiffParentOid
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  bool get _canOpenFile {
    if (_isCommitBackedDiff) {
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
    _cancelReadingDiff();
    _readingDiffGeneration += 1;
    final backend = ref.read(gitBackendProvider);
    final scope = widget.tab.gitDiffScope;
    final filePath = widget.tab.filePath;
    final sourceControlScope = _sourceControlScope;
    final sourceFilePath = sourceControlScope.toSourceRelativePath(filePath);
    final sourceOldPath = sourceControlScope.toSourceRelativePath(
      widget.tab.gitDiffOldPath,
    );
    final area = widget.tab.gitDiffArea;
    final nextFuture = _isCommitBackedDiff
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
      _readingDiffResult = null;
      _readingDiffOriginalSnapshot = null;
      _showReadingDiff = false;
      _readingDiffBusy = false;
      _readingDiffProgress = null;
      _readingDiffError = null;
      _readingDiffAgentLabel = null;
      _readingDiffModel = null;
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

  ReadingDiffRequest _readingDiffRequest({bool ignoreCache = false}) {
    final scope = widget.tab.gitDiffScope;
    final sourceControlScope = _sourceControlScope;
    final sourceFilePath = sourceControlScope.toSourceRelativePath(
      widget.tab.filePath,
    );
    final sourceOldPath = sourceControlScope.toSourceRelativePath(
      widget.tab.gitDiffOldPath,
    );
    return ReadingDiffRequest(
      workspacePath: sourceControlScope.path,
      settings: ref.read(settingsControllerProvider).aiTextGeneration,
      filePath: scope == WorkspaceGitDiffScope.all ? null : sourceFilePath,
      oldPath: scope == WorkspaceGitDiffScope.all ? null : sourceOldPath,
      area: scope == WorkspaceGitDiffScope.file ? widget.tab.gitDiffArea : null,
      commitOid: _isCommitBackedDiff ? widget.tab.gitDiffCommitOid : null,
      parentOid: _isCommitBackedDiff ? widget.tab.gitDiffParentOid : null,
      ignoreCache: ignoreCache,
    );
  }

  Future<void> _generateReadingDiff({bool ignoreCache = false}) async {
    if (_readingDiffBusy) {
      return;
    }
    final request = _readingDiffRequest(ignoreCache: ignoreCache);
    final generation = ++_readingDiffGeneration;
    setState(() {
      _readingDiffBusy = true;
      _readingDiffProgress = const ReadingDiffGenerationProgress(
        stage: ReadingDiffGenerationStage.preparing,
        completedChunks: 0,
        totalChunks: 0,
      );
      _readingDiffError = null;
      _readingDiffAgentLabel = null;
      _readingDiffModel = null;
    });
    try {
      final service = ref.read(readingDiffServiceProvider);
      final preparation = await service.prepare(request);
      if (!mounted || generation != _readingDiffGeneration) {
        return;
      }
      setState(() {
        _readingDiffAgentLabel = preparation.agent.label;
        _readingDiffModel = preparation.model;
      });
      if (preparation.cachedResult == null) {
        setState(() {
          _readingDiffBusy = false;
          _readingDiffProgress = null;
        });
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) =>
              ReadingDiffConfirmationDialog(preparation: preparation),
        );
        if (!mounted ||
            confirmed != true ||
            generation != _readingDiffGeneration) {
          return;
        }
        setState(() {
          _readingDiffBusy = true;
          _readingDiffProgress = ReadingDiffGenerationProgress(
            stage: ReadingDiffGenerationStage.generating,
            completedChunks: 0,
            totalChunks: preparation.chunkCount,
            currentChunk: 1,
          );
        });
      }
      _activeReadingDiffRequest = request;
      final result = await service.generate(
        preparation,
        onProgress: (progress) {
          if (!mounted || generation != _readingDiffGeneration) {
            return;
          }
          setState(() => _readingDiffProgress = progress);
        },
      );
      if (!mounted || generation != _readingDiffGeneration) {
        return;
      }
      setState(() {
        _readingDiffResult = result;
        _readingDiffOriginalSnapshot = preparation.rawDiff;
        _showReadingDiff = true;
        _readingDiffProgress = null;
        _readingDiffError = null;
      });
    } on AiTextGenerationCanceledException {
      return;
    } catch (error) {
      if (mounted && generation == _readingDiffGeneration) {
        setState(() {
          _readingDiffError = error is AiTextGenerationException
              ? error.message
              : 'Could not generate the reading diff.';
        });
      }
    } finally {
      if (identical(_activeReadingDiffRequest, request)) {
        _activeReadingDiffRequest = null;
      }
      if (mounted && generation == _readingDiffGeneration) {
        setState(() {
          _readingDiffBusy = false;
          _readingDiffProgress = null;
        });
      }
    }
  }

  void _cancelReadingDiff() {
    final activeRequest = _activeReadingDiffRequest;
    if (activeRequest != null) {
      ref.read(readingDiffServiceProvider).cancel(activeRequest);
      _activeReadingDiffRequest = null;
    }
    _readingDiffGeneration += 1;
    if (mounted && _readingDiffBusy) {
      setState(() {
        _readingDiffBusy = false;
        _readingDiffProgress = null;
      });
    }
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

  bool get _isCommitBackedDiff => switch (widget.tab.gitDiffSource) {
    WorkspaceGitDiffSource.commit || WorkspaceGitDiffSource.pullRequest => true,
    WorkspaceGitDiffSource.workingTree => false,
  };

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
