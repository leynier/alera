import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
import 'package:alera/src/features/workbench/application/editor_autosave_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:code_forge/code_forge.dart' as code_forge;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

part 'workspace_editor_language_registry.dart';
part 'workspace_editor_widgets.dart';
part 'workspace_editor_focus.dart';
part 'workspace_editor_reveal.dart';
part 'workspace_editor_loading.dart';
part 'workspace_editor_save.dart';
part 'workspace_editor_text_actions.dart';

class const WorkspaceEditorSurface({
  super.key,
  required final Workspace workspace,
  final WorkspaceSourceControlScope? sourceControlScope,
  required final WorkspaceTabRecord tab,
  required final bool autofocus,
  final ValueChanged<String>? onOpenMermanPreview,
  required final ValueChanged<String> onOpenMarkdownViewerTab,
  final VoidCallback? onKeepPreview,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<WorkspaceEditorSurface> createState() =>
      _WorkspaceEditorSurfaceState();
}

class _WorkspaceEditorSurfaceState
    extends ConsumerState<WorkspaceEditorSurface> {
  late final code_forge.CodeForgeController _controller;
  late final code_forge.UndoRedoController _undoController;
  late final code_forge.FindController _findController;
  late WorkspaceEditorFocusNode _focusNode;
  late final WorkspaceFileService _workspaceFiles;
  late final EditorSessionRegistry _editorSessions;
  late final EditorSessionHandle _sessionHandle;
  late final EditorAutosaveController _autosave;
  late EditorDocumentSession _document;
  Object? _loadError;
  bool _loading = true;
  bool _saving = false;
  bool _stateRefreshQueued = false;
  Offset? _lastSecondaryTapGlobalPosition;
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    _controller = code_forge.CodeForgeController();
    _applyEditorSettings(
      normalizeWorkspaceEditorTabSize(
        ref.read(settingsControllerProvider).editor.tabSize,
      ),
    );
    _undoController = code_forge.UndoRedoController();
    _findController = code_forge.FindController(_controller);
    _focusNode = WorkspaceEditorFocusNode();
    _workspaceFiles = ref.read(workspaceFileServiceProvider);
    _editorSessions = ref.read(editorSessionRegistryProvider);
    _sessionHandle = EditorSessionHandle(
      isDirty: _isDirty,
      save: _save,
      discard: _discardChanges,
      reveal: _revealOrDefer,
      reload: _reloadFromDiskAfterExternalChange,
    );
    _controller.addListener(_handleControllerChanged);
    _document = _editorSessions.documentFor(widget.tab.id);
    final editorSettings = ref.read(settingsControllerProvider).editor;
    _autosave = EditorAutosaveController(
      enabled: editorSettings.autosaveEnabled,
      debounce: editorSettings.autosaveDebounce,
      isDirty: _isDirty,
      isReady: _isReadyForAutosave,
      save: _saveAutomatically,
      onError: _handleAutosaveError,
    );
    ref.listenManual(
      settingsControllerProvider.select((settings) => settings.editor),
      (previous, next) => _autosave.updateSettings(
        enabled: next.autosaveEnabled,
        debounce: next.autosaveDebounce,
      ),
    );
    _registerSession(widget.tab.id);
    _restoreDocumentOrLoad();
  }

  @override
  void didUpdateWidget(covariant WorkspaceEditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id != widget.tab.id ||
        oldWidget.workspace.path != widget.workspace.path ||
        oldWidget.tab.filePath != widget.tab.filePath) {
      _autosave.cancelPending();
      _replaceFocusNode();
      _editorSessions.unregister(oldWidget.tab.id, _sessionHandle);
      _document = _editorSessions.documentFor(widget.tab.id);
      if (oldWidget.tab.id == widget.tab.id &&
          oldWidget.tab.filePath != widget.tab.filePath) {
        _document.clearSnapshot();
      }
      _registerSession(widget.tab.id);
      _restoreDocumentOrLoad();
    }
  }

  @override
  void dispose() {
    _autosave.dispose();
    _editorSessions.unregister(widget.tab.id, _sessionHandle);
    _focusNode.suppressThirdPartyListeners();
    _focusNode.unfocus();
    _controller.removeListener(_handleControllerChanged);
    _findController.dispose();
    _undoController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      return const _EditorMessage(message: 'This editor tab has no file.');
    }
    final editorSettings = ref.watch(
      settingsControllerProvider.select((settings) => settings.editor),
    );
    final effectiveTabSize = normalizeWorkspaceEditorTabSize(
      editorSettings.tabSize,
    );
    _applyEditorSettings(effectiveTabSize);
    final editorTheme = editorSyntaxThemeForName(editorSettings.themeName);
    final rootStyle = editorSyntaxRootStyleForName(editorSettings.themeName);
    final effectiveThemeName =
        editorSyntaxThemeEntryForName(editorSettings.themeName)?.name ??
        EditorSyntaxThemeNames.alera;
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_loadError case final loadError?) {
      content = _EditorMessage(message: _messageFor(loadError));
    } else {
      content = Stack(
        children: <Widget>[
          Listener(
            onPointerDown: _captureEditorPointerDown,
            child: code_forge.CodeForge(
              key: ValueKey<String>(
                workspaceEditorCodeForgeKey(
                  tabId: widget.tab.id,
                  filePath: filePath,
                  themeName: effectiveThemeName,
                ),
              ),
              controller: _controller,
              undoController: _undoController,
              findController: _findController,
              focusNode: _focusNode,
              autoFocus: widget.autofocus,
              lineWrap: true,
              enableLocalSuggestions: false,
              enableGuideLines: true,
              enableGutter: true,
              enableGutterDivider: false,
              editorTheme: editorTheme,
              language: _languageForPath(filePath),
              tabSize: effectiveTabSize,
              useSpaceAsTab: true,
              scrollbarDecoration: _scrollbarDecoration(),
              suggestionStyle: _editorOverlayStyle(context),
              customContextMenuItems: _editorTextActionMenuItems(context),
              textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: 'JetBrains Mono',
                color: rootStyle.color ?? AleraTokens.foreground,
                height: 1.35,
              ),
            ),
          ),
          if (_saving)
            const Positioned(
              top: AleraTokens.space8,
              right: AleraTokens.space8,
              child: SizedBox.square(
                dimension: AleraTokens.space16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.bg),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          _EditorFileBar(
            path: workspaceEditorDisplayPath(
              workspace: widget.workspace,
              filePath: filePath,
            ),
            dirty: _document.isDirty,
            saving: _saving,
            onViewDiff: !_loading ? () => unawaited(_openDiffForFile()) : null,
            onSave: _document.isDirty && !_loading && !_saving
                ? () => unawaited(_save())
                : null,
            onDiscard: _document.isDirty && !_loading && !_saving
                ? () => unawaited(_discardChanges())
                : null,
            onOpenPreview: _openPreviewActionFor(filePath),
          ),
          const Divider(height: 1, color: AleraTokens.borderSubtle),
          Expanded(child: content),
        ],
      ),
    );
  }

  VoidCallback? _openPreviewActionFor(String filePath) {
    if (isWorkspaceMermanFilePath(filePath) &&
        widget.onOpenMermanPreview != null) {
      return () => widget.onOpenMermanPreview?.call(filePath);
    }
    if (isWorkspaceMarkdownFilePath(filePath)) {
      return () => widget.onOpenMarkdownViewerTab(filePath);
    }
    return null;
  }

  Future<void> _openDiffForFile() async {
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      return;
    }
    final diffTarget = workspaceEditorDiffTargetForFile(
      workspace: widget.workspace,
      filePath: filePath,
      sourceControlScope: widget.sourceControlScope,
    );
    if (diffTarget == null) {
      _showToast('No Git diff for this file');
      return;
    }
    try {
      final status = await ref
          .read(gitBackendProvider)
          .statusForPath(
            path: diffTarget.gitPath,
            filePath: diffTarget.gitFilePath,
          );
      final entries = status.entriesForPath(diffTarget.gitFilePath);
      if (!mounted) {
        return;
      }
      if (entries.isEmpty) {
        _showToast('No Git diff for this file');
        return;
      }
      if (entries.length == 1) {
        await ref
            .read(workbenchControllerProvider.notifier)
            .openGitDiffTab(
              workspace: widget.workspace,
              relativePath: filePath,
              area: entries.single.area,
              scope: .file,
              gitDiffRoot: diffTarget.gitDiffRoot,
              preview: true,
            );
        return;
      }
      final choice = await _showDiffChoiceMenu(entries);
      if (!mounted || choice == null) {
        return;
      }
      if (choice.allForFile) {
        await ref
            .read(workbenchControllerProvider.notifier)
            .openGitDiffTab(
              workspace: widget.workspace,
              relativePath: filePath,
              scope: .fileAll,
              gitDiffRoot: diffTarget.gitDiffRoot,
              preview: true,
            );
        return;
      }
      await ref
          .read(workbenchControllerProvider.notifier)
          .openGitDiffTab(
            workspace: widget.workspace,
            relativePath: filePath,
            area: choice.area,
            scope: .file,
            gitDiffRoot: diffTarget.gitDiffRoot,
            preview: true,
          );
    } catch (_) {
      if (mounted) {
        _showToast('Could not open Git diff', tone: .error);
      }
    }
  }

  Future<_DiffOpenChoice?> _showDiffChoiceMenu(List<GitChangeEntry> entries) {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    return showMenu<_DiffOpenChoice>(
      context: context,
      position: .fromLTRB(
        overlay.size.width - 280,
        AleraTokens.sidebarHeaderHeight,
        AleraTokens.space16,
        0,
      ),
      items: <PopupMenuEntry<_DiffOpenChoice>>[
        for (final entry in entries)
          PopupMenuItem<_DiffOpenChoice>(
            value: _DiffOpenChoice(area: entry.area),
            child: Text('${entry.area.label} changes'),
          ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const PopupMenuItem<_DiffOpenChoice>(
          value: _DiffOpenChoice(allForFile: true),
          child: Text('All changes for file'),
        ),
      ],
    );
  }

  bool _isDirty() => _document.isDirty;

  void _refreshStateSafely() {
    if (!mounted) {
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      setState(() {});
      return;
    }
    if (_stateRefreshQueued) {
      return;
    }
    _stateRefreshQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _stateRefreshQueued = false;
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _setEditorState(VoidCallback update) {
    setState(update);
  }

  void _registerSession(String tabId) {
    _editorSessions.register(tabId, _sessionHandle);
  }

  void _replaceFocusNode() {
    final previous = _focusNode;
    previous.suppressThirdPartyListeners();
    previous.unfocus();
    _focusNode = WorkspaceEditorFocusNode();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      previous.dispose();
    });
  }

  void _applyEditorSettings(int tabSize) {
    if (_controller.tabSize != tabSize) {
      _controller.tabSize = tabSize;
    }
    if (!_controller.useSpaceAsTab) {
      _controller.useSpaceAsTab = true;
    }
  }

  int _currentEditorTabSize() {
    return normalizeWorkspaceEditorTabSize(
      ref.read(settingsControllerProvider).editor.tabSize,
    );
  }

  void _showToast(String message, {AleraToastTone tone = AleraToastTone.info}) {
    if (!mounted) {
      return;
    }
    AleraToast.show(context, message: message, tone: tone);
  }

  String _messageFor(Object error) {
    if (error is native.WorkspaceFileError) {
      return switch (error.kind) {
        native.WorkspaceFileErrorKind.unsupported => 'File cannot be edited',
        native.WorkspaceFileErrorKind.notFound => 'File not found',
        native.WorkspaceFileErrorKind.outsideWorkspace =>
          'File is outside the workspace',
        native.WorkspaceFileErrorKind.protectedPath => 'File is protected',
        native.WorkspaceFileErrorKind.conflict => 'File changed on disk',
        _ => 'File operation failed',
      };
    }
    return 'File operation failed';
  }

  code_forge.ScrollbarDecoration _scrollbarDecoration() {
    return const code_forge.ScrollbarDecoration(
      showLineNumberIndicator: false,
      thickness: 0,
      thumbColor: Colors.transparent,
      trackVisibility: false,
      trackColor: Colors.transparent,
      trackBorderColor: Colors.transparent,
    );
  }
}

class const _DiffOpenChoice({
  final GitChangeArea? area,
  final bool allForFile = false,
});

typedef WorkspaceEditorDiffTarget = ({
  String gitPath,
  String gitFilePath,
  String? gitDiffRoot,
});

@visibleForTesting
WorkspaceEditorDiffTarget? workspaceEditorDiffTargetForFile({
  required Workspace workspace,
  required String filePath,
  required WorkspaceSourceControlScope? sourceControlScope,
}) {
  final sourceFilePath = sourceControlScope?.toSourceRelativePath(filePath);
  if (sourceControlScope != null && sourceFilePath == null) {
    return null;
  }
  return (
    gitPath: sourceControlScope?.path ?? workspace.path,
    gitFilePath: sourceFilePath ?? filePath,
    gitDiffRoot: sourceControlScope?.relativeRoot,
  );
}

String workspaceEditorDisplayPath({
  required Workspace workspace,
  required String filePath,
}) {
  if (!p.isAbsolute(filePath)) {
    return filePath;
  }
  final workspacePath = p.normalize(workspace.path);
  final normalizedFilePath = p.normalize(filePath);
  if (p.equals(normalizedFilePath, workspacePath) ||
      p.isWithin(workspacePath, normalizedFilePath)) {
    return p.relative(normalizedFilePath, from: workspacePath);
  }
  return filePath;
}
