import 'dart:async';
import 'dart:typed_data';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_errors.dart';
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
part 'workspace_git_diff_surface_loading.dart';

class const WorkspaceGitDiffSurface({
  super.key,
  required final Workspace workspace,
  required final WorkspaceTabRecord tab,
}) extends ConsumerStatefulWidget {
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
  Completer<void>? _readingDiffCompletion;
  bool _readingDiffCancelRequested = false;
  int _readingDiffGeneration = 0;
  int _diffLoadGeneration = 0;

  void _updateDiffState(VoidCallback update) => setState(update);

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
    final aiAssistEnabled = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.aiAssist.enabled,
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.bg),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          _GitDiffBar(
            title: widget.tab.title,
            filePath: filePath,
            onRefresh: _load,
            onOpenFile: _canOpenFile ? () => unawaited(_openFile()) : null,
            aiAssistEnabled: aiAssistEnabled,
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
      settings: ref.read(settingsControllerProvider).aiAssist,
      filePath: scope == WorkspaceGitDiffScope.all ? null : sourceFilePath,
      oldPath: scope == WorkspaceGitDiffScope.all ? null : sourceOldPath,
      area: scope == WorkspaceGitDiffScope.file ? widget.tab.gitDiffArea : null,
      commitOid: _isCommitBackedDiff ? widget.tab.gitDiffCommitOid : null,
      parentOid: _isCommitBackedDiff ? widget.tab.gitDiffParentOid : null,
      ignoreCache: ignoreCache,
    );
  }

  Future<void> _generateReadingDiff({bool ignoreCache = false}) async {
    if (_readingDiffBusy || _readingDiffCompletion != null) {
      return;
    }
    final request = _readingDiffRequest(ignoreCache: ignoreCache);
    final generation = ++_readingDiffGeneration;
    final completion = Completer<void>();
    _activeReadingDiffRequest = request;
    _readingDiffCompletion = completion;
    _readingDiffCancelRequested = false;
    setState(() {
      _readingDiffBusy = true;
      _readingDiffProgress = const ReadingDiffGenerationProgress(
        stage: .preparing,
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
      if (!mounted ||
          generation != _readingDiffGeneration ||
          _readingDiffCancelRequested) {
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
            generation != _readingDiffGeneration ||
            _readingDiffCancelRequested) {
          return;
        }
        setState(() {
          _readingDiffBusy = true;
          _readingDiffProgress = ReadingDiffGenerationProgress(
            stage: .generating,
            completedChunks: 0,
            totalChunks: preparation.chunkCount,
            currentChunk: 1,
          );
        });
      }
      final result = await service.generate(
        preparation,
        onProgress: (progress) {
          if (!mounted || generation != _readingDiffGeneration) {
            return;
          }
          setState(() => _readingDiffProgress = progress);
        },
      );
      if (!mounted ||
          generation != _readingDiffGeneration ||
          _readingDiffCancelRequested) {
        return;
      }
      setState(() {
        _readingDiffResult = result;
        _readingDiffOriginalSnapshot = preparation.rawDiff;
        _showReadingDiff = true;
        _readingDiffProgress = null;
        _readingDiffError = null;
      });
    } on AiAssistCanceledException {
      return;
    } catch (error) {
      if (mounted && generation == _readingDiffGeneration) {
        setState(() {
          _readingDiffError = error is AiAssistException
              ? error.message
              : 'Could not generate the reading diff.';
        });
      }
    } finally {
      if (identical(_activeReadingDiffRequest, request)) {
        _activeReadingDiffRequest = null;
        _readingDiffCancelRequested = false;
      }
      if (mounted && generation == _readingDiffGeneration) {
        setState(() {
          _readingDiffBusy = false;
          _readingDiffProgress = null;
        });
      }
      if (identical(_readingDiffCompletion, completion)) {
        _readingDiffCompletion = null;
      }
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
  }

  void _cancelReadingDiff() {
    final activeRequest = _activeReadingDiffRequest;
    if (activeRequest != null && !_readingDiffCancelRequested) {
      _readingDiffCancelRequested = true;
      ref.read(readingDiffServiceProvider).cancel(activeRequest);
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
