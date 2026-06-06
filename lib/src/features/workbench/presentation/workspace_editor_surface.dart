import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:code_forge/code_forge.dart' as code_forge;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

part 'workspace_editor_language_registry.dart';
part 'workspace_editor_widgets.dart';
part 'workspace_editor_focus.dart';

class WorkspaceEditorSurface extends ConsumerStatefulWidget {
  const WorkspaceEditorSurface({
    super.key,
    required this.workspace,
    required this.tab,
    required this.autofocus,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final bool autofocus;

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
  late EditorDocumentSession _document;
  Object? _loadError;
  bool _loading = true;
  bool _saving = false;
  bool _stateRefreshQueued = false;

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
    );
    _controller.addListener(_handleControllerChanged);
    _document = _editorSessions.documentFor(widget.tab.id);
    _registerSession(widget.tab.id);
    _restoreDocumentOrLoad();
  }

  @override
  void didUpdateWidget(covariant WorkspaceEditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id != widget.tab.id ||
        oldWidget.tab.filePath != widget.tab.filePath) {
      _replaceFocusNode();
      _editorSessions.unregister(oldWidget.tab.id, _sessionHandle);
      _document = _editorSessions.documentFor(widget.tab.id);
      _registerSession(widget.tab.id);
      _restoreDocumentOrLoad();
    }
  }

  @override
  void dispose() {
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
          code_forge.CodeForge(
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
            enableGutterDivider: true,
            editorTheme: editorTheme,
            language: _languageForPath(filePath),
            tabSize: effectiveTabSize,
            useSpaceAsTab: true,
            scrollbarDecoration: _scrollbarDecoration(),
            textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'JetBrains Mono',
              color: rootStyle.color ?? AleraTokens.foreground,
              height: 1.35,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _EditorFileBar(
            path: workspaceEditorDisplayPath(
              workspace: widget.workspace,
              filePath: filePath,
            ),
            dirty: _document.isDirty,
            saving: _saving,
            onSave: _document.isDirty && !_loading && !_saving
                ? () => unawaited(_save())
                : null,
            onDiscard: _document.isDirty && !_loading && !_saving
                ? () => unawaited(_discardChanges())
                : null,
          ),
          const Divider(height: 1, color: AleraTokens.borderSubtle),
          Expanded(child: content),
        ],
      ),
    );
  }

  Future<void> _load() async {
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final tabSize = _currentEditorTabSize();
      final file = await _workspaceFiles.readEditorTextFile(
        workspacePath: widget.workspace.path,
        relativePath: filePath,
        tabSize: tabSize,
      );
      if (!mounted) {
        return;
      }
      _document.acceptLoaded(file, tabSize: tabSize);
      _controller.text = _document.currentText ?? '';
    } catch (error) {
      if (!mounted) {
        return;
      }
      _document.acceptLoadError(error);
      _loadError = error;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    final filePath = widget.tab.filePath;
    if (filePath == null || _loading || _saving) {
      return;
    }
    final loadError = _loadError;
    if (loadError != null) {
      _showToast(_messageFor(loadError), tone: AleraToastTone.error);
      return;
    }
    if (!_document.canSave) {
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await _write(overwriteIfChanged: false);
      if (!mounted) {
        return;
      }
      _acceptSaved(saved);
      _showToast('File saved');
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is native.WorkspaceFileError &&
          error.kind == native.WorkspaceFileErrorKind.conflict) {
        await _resolveSaveConflict();
      } else {
        _showToast(_messageFor(error), tone: AleraToastTone.error);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _discardChanges() async {
    if (_loading || _saving || !_document.canSave) {
      return;
    }
    final loadedText = _document.loadedText;
    if (loadedText == null) {
      return;
    }
    _document.updateCurrentText(loadedText);
    _controller.text = loadedText;
    _undoController.clear();
    if (mounted) {
      setState(() {});
      _showToast('Changes discarded');
    }
  }

  Future<void> _resolveSaveConflict() async {
    final overwrite = await showDialog<bool>(
      context: context,
      builder: (context) => const AleraConfirmDialog(
        title: 'File changed on disk',
        message: 'Overwrite the file with the editor contents?',
        confirmLabel: 'Overwrite',
        destructive: true,
      ),
    );
    if (overwrite != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    final saved = await _write(overwriteIfChanged: true);
    if (!mounted) {
      return;
    }
    _acceptSaved(saved);
    _showToast('File overwritten');
  }

  Future<native.WorkspaceEditorTextFile> _write({
    required bool overwriteIfChanged,
  }) {
    return _workspaceFiles.writeEditorTextFile(
      workspacePath: widget.workspace.path,
      relativePath: widget.tab.filePath!,
      currentDisplayContent: _controller.text,
      originalRawContent: _document.loadedRawText,
      originalDisplayContent: _document.loadedText,
      expectedContentToken: _document.contentToken,
      overwriteIfChanged: overwriteIfChanged,
      tabSize: _currentEditorTabSize(),
    );
  }

  void _acceptSaved(native.WorkspaceEditorTextFile saved) {
    _document.acceptSaved(saved, tabSize: _currentEditorTabSize());
    _controller.text = _document.currentText ?? '';
  }

  bool _isDirty() => _document.isDirty;

  void _handleControllerChanged() {
    _document.updateCurrentText(_controller.text);
    _refreshStateSafely();
  }

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

  void _restoreDocumentOrLoad() {
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      _loading = false;
      return;
    }
    _document.attachFile(
      workspacePath: widget.workspace.path,
      relativePath: filePath,
    );
    if (_document.hasSnapshot) {
      _controller.text = _document.currentText ?? '';
      _loadError = _document.loadError;
      _loading = false;
      return;
    }
    unawaited(_load());
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

@visibleForTesting
String workspaceEditorCodeForgeKey({
  required String tabId,
  required String filePath,
  required String themeName,
}) {
  return 'workspace-editor-$tabId-$filePath-$themeName';
}

class _EditorMessage extends StatelessWidget {
  const _EditorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}
