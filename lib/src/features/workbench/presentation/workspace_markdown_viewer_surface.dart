import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_text_selection_toolbar.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_editor_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_markdown_uri_policy.dart';
import 'package:alera/src/features/workbench/presentation/workspace_markdown_viewer_images.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class const WorkspaceMarkdownViewerSurface({
  super.key,
  required final Workspace workspace,
  required final WorkspaceTabRecord tab,
  required final ValueChanged<String> onOpenEditorTab,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<WorkspaceMarkdownViewerSurface> createState() =>
      _WorkspaceMarkdownViewerSurfaceState();
}

class _WorkspaceMarkdownViewerSurfaceState
    extends ConsumerState<WorkspaceMarkdownViewerSurface> {
  late final WorkspaceFileService _workspaceFiles;
  late final EditorSessionRegistry _editorSessions;
  String? _content;
  Object? _loadError;
  bool _loading = true;
  bool _usingDirtyEditorContent = false;
  int _loadRequestId = 0;
  Listenable? _editorDocumentChanges;
  bool _editorUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _workspaceFiles = ref.read(workspaceFileServiceProvider);
    _editorSessions = ref.read(editorSessionRegistryProvider);
    _subscribeToEditorDocument();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant WorkspaceMarkdownViewerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.path != widget.workspace.path ||
        oldWidget.tab.filePath != widget.tab.filePath) {
      _subscribeToEditorDocument();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _editorDocumentChanges?.removeListener(_handleEditorSessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      return const _MarkdownViewerMessage(
        message: 'This markdown viewer tab has no file.',
      );
    }

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_loadError case final loadError?) {
      content = _MarkdownViewerMessage(message: _messageFor(loadError));
    } else {
      content = SelectionArea(
        contextMenuBuilder: AleraTextSelectionToolbar.selectableRegion,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AleraTokens.space24),
          child: GptMarkdownTheme(
            gptThemeData: GptMarkdownThemeData(
              brightness: .dark,
              linkColor: AleraTokens.info,
              highlightColor: AleraTokens.accentSubtle,
            ),
            child: DefaultTextStyle(
              style:
                  Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AleraTokens.foreground, height: 1.45) ??
                  const TextStyle(color: AleraTokens.foreground, height: 1.45),
              child: GptMarkdown(
                _content ?? '',
                imageBuilder: _buildImage,
                onLinkTap: (url, _) => unawaited(_openLink(url)),
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.bg),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          _MarkdownViewerFileBar(
            path: workspaceEditorDisplayPath(
              workspace: widget.workspace,
              filePath: filePath,
            ),
            loading: _loading,
            onRefresh: () => unawaited(_load()),
            onOpenEditor: () => widget.onOpenEditorTab(filePath),
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
    final dirtyEditorContent = _dirtyEditorContentForCurrentFile();
    if (dirtyEditorContent != null) {
      if (!shouldUpdateMarkdownViewerDirtyContent(
        currentContent: _content,
        dirtyEditorContent: dirtyEditorContent,
        loading: _loading,
        loadError: _loadError,
        usingDirtyEditorContent: _usingDirtyEditorContent,
      )) {
        return;
      }
      _loadRequestId += 1;
      setState(() {
        _content = dirtyEditorContent;
        _loadError = null;
        _loading = false;
        _usingDirtyEditorContent = true;
      });
      return;
    }
    final requestId = ++_loadRequestId;
    setState(() {
      _loading = true;
      _loadError = null;
      _usingDirtyEditorContent = false;
    });
    try {
      final file = await _workspaceFiles.readTextFile(
        workspacePath: widget.workspace.path,
        relativePath: filePath,
      );
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      final latestDirtyEditorContent = _dirtyEditorContentForCurrentFile();
      setState(() {
        _content = latestDirtyEditorContent ?? file.content;
        _loadError = null;
        _loading = false;
        _usingDirtyEditorContent = latestDirtyEditorContent != null;
      });
    } catch (error) {
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      final latestDirtyEditorContent = _dirtyEditorContentForCurrentFile();
      setState(() {
        _content = latestDirtyEditorContent;
        _loadError = latestDirtyEditorContent == null ? error : null;
        _loading = false;
        _usingDirtyEditorContent = latestDirtyEditorContent != null;
      });
    }
  }

  void _handleEditorSessionChanged() {
    if (!mounted || _editorUpdateScheduled) {
      return;
    }
    _editorUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editorUpdateScheduled = false;
      if (mounted) {
        _applyEditorSessionChange();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _applyEditorSessionChange() {
    final dirtyEditorContent = _dirtyEditorContentForCurrentFile();
    if (dirtyEditorContent != null) {
      _loadRequestId += 1;
      setState(() {
        _content = dirtyEditorContent;
        _loadError = null;
        _loading = false;
        _usingDirtyEditorContent = true;
      });
      return;
    }
    if (_usingDirtyEditorContent) {
      unawaited(_load());
    }
  }

  void _subscribeToEditorDocument() {
    _editorDocumentChanges?.removeListener(_handleEditorSessionChanged);
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      _editorDocumentChanges = null;
      return;
    }
    _editorDocumentChanges = _editorSessions.documentChangesForPath(
      workspacePath: widget.workspace.path,
      relativePath: filePath,
    )..addListener(_handleEditorSessionChanged);
  }

  String? _dirtyEditorContentForCurrentFile() {
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      return null;
    }
    return _editorSessions.dirtyTextForPath(
      workspacePath: widget.workspace.path,
      relativePath: filePath,
    );
  }

  Widget _buildImage(
    BuildContext context,
    String imageUrl,
    double? width,
    double? height,
  ) {
    return buildMarkdownViewerImage(
      workspacePath: widget.workspace.path,
      markdownPath: widget.tab.filePath,
      imageUrl: imageUrl,
      width: width,
      height: height,
    );
  }

  Future<void> _openLink(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (!isSupportedMarkdownViewerLinkUri(uri)) {
      _showToast('Link cannot be opened', tone: .error);
      return;
    }
    try {
      await ref.read(externalUriLauncherProvider).open(uri!);
    } catch (_) {
      _showToast('Link cannot be opened', tone: .error);
    }
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
        native.WorkspaceFileErrorKind.unsupported => 'File cannot be previewed',
        native.WorkspaceFileErrorKind.notFound => 'File not found',
        native.WorkspaceFileErrorKind.outsideWorkspace =>
          'File is outside the workspace',
        native.WorkspaceFileErrorKind.protectedPath => 'File is protected',
        _ => 'File operation failed',
      };
    }
    return 'File operation failed';
  }
}

@visibleForTesting
bool shouldUpdateMarkdownViewerDirtyContent({
  required String? currentContent,
  required String dirtyEditorContent,
  required bool loading,
  required Object? loadError,
  required bool usingDirtyEditorContent,
}) {
  return loading ||
      loadError != null ||
      !usingDirtyEditorContent ||
      currentContent != dirtyEditorContent;
}

class const _MarkdownViewerFileBar({
  required final String path,
  required final bool loading,
  required final VoidCallback onRefresh,
  required final VoidCallback onOpenEditor,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            AleraFileIcon(
              pathOrName: path,
              kind: .file,
              size: 16,
              fallbackColor: AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: .ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            AleraIconButton(
              tooltip: loading ? 'Refreshing preview' : 'Refresh preview',
              icon: loading ? AleraIcons.loading : AleraIcons.refresh,
              onPressed: loading ? null : onRefresh,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Open source file',
              icon: AleraIcons.code,
              onPressed: onOpenEditor,
            ),
          ],
        ),
      ),
    );
  }
}

class const _MarkdownViewerMessage({required final String message})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}
