import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_editor_surface.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

class WorkspacePdfViewerSurface extends ConsumerStatefulWidget {
  const WorkspacePdfViewerSurface({
    super.key,
    required this.workspace,
    required this.tab,
    required this.autofocus,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final bool autofocus;

  @override
  ConsumerState<WorkspacePdfViewerSurface> createState() =>
      _WorkspacePdfViewerSurfaceState();
}

class _WorkspacePdfViewerSurfaceState
    extends ConsumerState<WorkspacePdfViewerSurface> {
  late final WorkspaceFileService _workspaceFiles;
  late final FocusNode _focusNode;
  late final TextEditingController _searchController;
  late final PdfViewerController _pdfController;
  ResolvedWorkspaceFile? _resolvedFile;
  Object? _loadError;
  bool _loading = true;
  bool _outlineOpen = false;
  bool _outlineLoading = false;
  List<PdfOutlineNode> _outline = const <PdfOutlineNode>[];
  PdfTextSearcher? _textSearcher;
  int? _pageNumber;
  int? _pageCount;
  double? _zoom;
  int _loadGeneration = 0;
  int _outlineGeneration = 0;

  @override
  void initState() {
    super.initState();
    _workspaceFiles = ref.read(workspaceFileServiceProvider);
    _focusNode = FocusNode();
    _searchController = TextEditingController();
    _pdfController = PdfViewerController()..addListener(_handleViewerChanged);
    unawaited(_load());
    if (widget.autofocus) {
      _requestFocusNextFrame();
    }
  }

  @override
  void didUpdateWidget(covariant WorkspacePdfViewerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.path != widget.workspace.path ||
        oldWidget.tab.filePath != widget.tab.filePath) {
      unawaited(_load());
    }
    if (!oldWidget.autofocus && widget.autofocus) {
      _requestFocusNextFrame();
    }
  }

  @override
  void dispose() {
    _textSearcher?.dispose();
    _pdfController.removeListener(_handleViewerChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      return const _PdfViewerMessage(message: 'This tab has no PDF.');
    }

    final displayPath = workspaceEditorDisplayPath(
      workspace: widget.workspace,
      filePath: filePath,
    );
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_loadError case final error?) {
      content = _PdfViewerMessage(message: _messageFor(error));
    } else if (_resolvedFile case final resolvedFile?) {
      content = _PdfViewerLayout(
        resolvedFile: resolvedFile,
        controller: _pdfController,
        params: _viewerParams(),
        outlineOpen: _outlineOpen,
        outlineLoading: _outlineLoading,
        outline: _outline,
        onToggleOutline: () => setState(() => _outlineOpen = !_outlineOpen),
        onOpenOutlineNode: _goToOutlineNode,
      );
    } else {
      content = const _PdfViewerMessage(message: 'PDF cannot be opened');
    }

    return Listener(
      onPointerDown: (_) => _focusNode.requestFocus(),
      child: Focus(
        focusNode: _focusNode,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AleraTokens.bg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PdfViewerFileBar(path: displayPath),
              const Divider(height: 1, color: AleraTokens.borderSubtle),
              _PdfToolbar(
                searchController: _searchController,
                searcher: _textSearcher,
                pageNumber: _pageNumber,
                pageCount: _pageCount,
                zoom: _zoom,
                outlineOpen: _outlineOpen,
                outlineEnabled: _outline.isNotEmpty || _outlineLoading,
                onSearchChanged: _handleSearchChanged,
                onPreviousMatch: _goToPreviousMatch,
                onNextMatch: _goToNextMatch,
                onZoomOut: _zoomOut,
                onZoomIn: _zoomIn,
                onToggleOutline: () =>
                    setState(() => _outlineOpen = !_outlineOpen),
              ),
              const Divider(height: 1, color: AleraTokens.borderSubtle),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }

  PdfViewerParams _viewerParams() {
    final searcher = _textSearcher;
    return PdfViewerParams(
      backgroundColor: AleraTokens.bg,
      margin: AleraTokens.space16,
      matchTextColor: AleraTokens.accent.withValues(alpha: 0.28),
      activeMatchTextColor: AleraTokens.warning.withValues(alpha: 0.45),
      pagePaintCallbacks: searcher == null
          ? null
          : <PdfViewerPagePaintCallback>[searcher.pageTextMatchPaintCallback],
      loadingBannerBuilder: (_, _, _) =>
          const Center(child: CircularProgressIndicator()),
      errorBannerBuilder: (context, _, _, _) =>
          const _PdfViewerMessage(message: 'PDF cannot be opened'),
      onViewerReady: _handleViewerReady,
    );
  }

  void _requestFocusNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    _outlineGeneration += 1;
    final requestedWorkspacePath = widget.workspace.path;
    final filePath = widget.tab.filePath;
    _textSearcher?.dispose();
    _textSearcher = null;
    _searchController.clear();
    if (filePath == null) {
      setState(() {
        _resolvedFile = null;
        _loadError = null;
        _loading = false;
        _resetDocumentState();
      });
      return;
    }
    final requestedFilePath = filePath;
    setState(() {
      _resolvedFile = null;
      _loadError = null;
      _loading = true;
      _resetDocumentState();
    });
    try {
      final resolvedFile = await _workspaceFiles.resolveWorkspaceFilePath(
        workspacePath: requestedWorkspacePath,
        relativePath: requestedFilePath,
      );
      if (!_isCurrentLoad(
        generation,
        requestedWorkspacePath,
        requestedFilePath,
      )) {
        return;
      }
      setState(() {
        _resolvedFile = resolvedFile;
        _loading = false;
      });
    } catch (error) {
      if (!_isCurrentLoad(
        generation,
        requestedWorkspacePath,
        requestedFilePath,
      )) {
        return;
      }
      setState(() {
        _resolvedFile = null;
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _resetDocumentState() {
    _outline = const <PdfOutlineNode>[];
    _outlineLoading = false;
    _outlineOpen = false;
    _pageNumber = null;
    _pageCount = null;
    _zoom = null;
  }

  bool _isCurrentLoad(int generation, String workspacePath, String filePath) {
    return mounted &&
        _loadGeneration == generation &&
        widget.workspace.path == workspacePath &&
        widget.tab.filePath == filePath;
  }

  void _handleViewerReady(
    PdfDocument document,
    PdfViewerController controller,
  ) {
    if (!mounted || !identical(controller, _pdfController)) {
      return;
    }
    if (_textSearcher == null && controller.isReady) {
      final searcher = PdfTextSearcher(controller)
        ..addListener(_handleSearchChangedFromSearcher);
      setState(() {
        _textSearcher = searcher;
      });
      unawaited(_loadOutline(document));
    }
    _syncViewerState();
  }

  Future<void> _loadOutline(PdfDocument document) async {
    final generation = ++_outlineGeneration;
    setState(() {
      _outlineLoading = true;
      _outline = const <PdfOutlineNode>[];
    });
    try {
      final outline = await document.loadOutline();
      if (!mounted || generation != _outlineGeneration) {
        return;
      }
      setState(() {
        _outline = outline;
        _outlineLoading = false;
        _outlineOpen = outline.isNotEmpty;
      });
    } catch (_) {
      if (!mounted || generation != _outlineGeneration) {
        return;
      }
      setState(() {
        _outline = const <PdfOutlineNode>[];
        _outlineLoading = false;
      });
    }
  }

  void _handleViewerChanged() {
    _syncViewerState();
  }

  void _syncViewerState() {
    if (!mounted || !_pdfController.isReady) {
      return;
    }
    final nextPageNumber = _pdfController.pageNumber;
    final nextPageCount = _pdfController.pageCount;
    final nextZoom = _pdfController.currentZoom;
    if (_pageNumber == nextPageNumber &&
        _pageCount == nextPageCount &&
        _zoom == nextZoom) {
      return;
    }
    setState(() {
      _pageNumber = nextPageNumber;
      _pageCount = nextPageCount;
      _zoom = nextZoom;
    });
  }

  void _handleSearchChanged(String value) {
    final query = value.trim();
    final searcher = _textSearcher;
    if (searcher == null) {
      return;
    }
    if (query.isEmpty) {
      searcher.resetTextSearch();
      return;
    }
    searcher.startTextSearch(query);
  }

  void _handleSearchChangedFromSearcher() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _goToPreviousMatch() async {
    await _textSearcher?.goToPrevMatch();
  }

  Future<void> _goToNextMatch() async {
    await _textSearcher?.goToNextMatch();
  }

  Future<void> _zoomOut() async {
    if (_pdfController.isReady) {
      await _pdfController.zoomDown();
    }
  }

  Future<void> _zoomIn() async {
    if (_pdfController.isReady) {
      await _pdfController.zoomUp();
    }
  }

  Future<void> _goToOutlineNode(PdfOutlineNode node) async {
    await _pdfController.goToDest(node.dest);
  }

  String _messageFor(Object error) {
    if (error is native.WorkspaceFileError) {
      return switch (error.kind) {
        native.WorkspaceFileErrorKind.notFound => 'PDF not found',
        native.WorkspaceFileErrorKind.outsideWorkspace =>
          'PDF is outside the workspace',
        native.WorkspaceFileErrorKind.invalidPath => 'PDF path is invalid',
        _ => 'PDF cannot be opened',
      };
    }
    return 'PDF cannot be opened';
  }
}

class _PdfViewerFileBar extends StatelessWidget {
  const _PdfViewerFileBar({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            AleraFileIcon(
              pathOrName: path,
              kind: AleraFileIconKind.file,
              size: 16,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfToolbar extends StatelessWidget {
  const _PdfToolbar({
    required this.searchController,
    required this.searcher,
    required this.pageNumber,
    required this.pageCount,
    required this.zoom,
    required this.outlineOpen,
    required this.outlineEnabled,
    required this.onSearchChanged,
    required this.onPreviousMatch,
    required this.onNextMatch,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onToggleOutline,
  });

  final TextEditingController searchController;
  final PdfTextSearcher? searcher;
  final int? pageNumber;
  final int? pageCount;
  final double? zoom;
  final bool outlineOpen;
  final bool outlineEnabled;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPreviousMatch;
  final VoidCallback onNextMatch;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onToggleOutline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: AleraTokens.space48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            AleraIconButton(
              tooltip: outlineOpen ? 'Hide outline' : 'Show outline',
              icon: Icons.toc,
              onPressed: outlineEnabled ? onToggleOutline : null,
              iconColor: outlineOpen
                  ? AleraTokens.accent
                  : AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space8),
            SizedBox(
              width: 220,
              child: AleraTextField(
                controller: searchController,
                dense: true,
                hintText: 'Search PDF',
                prefixIcon: Icons.search,
                onChanged: onSearchChanged,
              ),
            ),
            const SizedBox(width: AleraTokens.space6),
            AleraIconButton(
              tooltip: 'Previous match',
              icon: Icons.keyboard_arrow_up,
              onPressed: searcher?.hasMatches == true ? onPreviousMatch : null,
            ),
            AleraIconButton(
              tooltip: 'Next match',
              icon: Icons.keyboard_arrow_down,
              onPressed: searcher?.hasMatches == true ? onNextMatch : null,
            ),
            const SizedBox(width: AleraTokens.space8),
            Text(
              _searchLabel(searcher),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const Spacer(),
            Text(
              _pageLabel(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
                fontFamily: 'JetBrains Mono',
              ),
            ),
            const SizedBox(width: AleraTokens.space12),
            AleraIconButton(
              tooltip: 'Zoom out',
              icon: Icons.remove,
              onPressed: zoom == null ? null : onZoomOut,
            ),
            Text(
              _zoomLabel(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
                fontFamily: 'JetBrains Mono',
              ),
            ),
            AleraIconButton(
              tooltip: 'Zoom in',
              icon: Icons.add,
              onPressed: zoom == null ? null : onZoomIn,
            ),
          ],
        ),
      ),
    );
  }

  String _searchLabel(PdfTextSearcher? searcher) {
    if (searcher == null) {
      return '';
    }
    if (searcher.isSearching) {
      final progress = searcher.searchProgress;
      if (progress == null) {
        return 'Searching...';
      }
      return 'Searching ${(progress * 100).clamp(0, 100).round()}%';
    }
    if (searcher.matches.isEmpty) {
      return searchController.text.trim().isEmpty ? '' : 'No matches';
    }
    final current = (searcher.currentIndex ?? 0) + 1;
    return '$current of ${searcher.matches.length}';
  }

  String _pageLabel() {
    if (pageNumber == null || pageCount == null) {
      return 'Page - of -';
    }
    return 'Page $pageNumber of $pageCount';
  }

  String _zoomLabel() {
    final value = zoom;
    if (value == null) {
      return '--%';
    }
    return '${(value * 100).round()}%';
  }
}

class _PdfViewerLayout extends StatelessWidget {
  const _PdfViewerLayout({
    required this.resolvedFile,
    required this.controller,
    required this.params,
    required this.outlineOpen,
    required this.outlineLoading,
    required this.outline,
    required this.onToggleOutline,
    required this.onOpenOutlineNode,
  });

  final ResolvedWorkspaceFile resolvedFile;
  final PdfViewerController controller;
  final PdfViewerParams params;
  final bool outlineOpen;
  final bool outlineLoading;
  final List<PdfOutlineNode> outline;
  final VoidCallback onToggleOutline;
  final ValueChanged<PdfOutlineNode> onOpenOutlineNode;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (outlineOpen)
          _PdfOutlinePanel(
            loading: outlineLoading,
            outline: outline,
            onClose: onToggleOutline,
            onOpenNode: onOpenOutlineNode,
          ),
        Expanded(
          child: PdfViewer.file(
            resolvedFile.path,
            key: workspacePdfViewerCacheKeyForTesting(resolvedFile),
            controller: controller,
            params: params,
          ),
        ),
      ],
    );
  }
}

class _PdfOutlinePanel extends StatelessWidget {
  const _PdfOutlinePanel({
    required this.loading,
    required this.outline,
    required this.onClose,
    required this.onOpenNode,
  });

  final bool loading;
  final List<PdfOutlineNode> outline;
  final VoidCallback onClose;
  final ValueChanged<PdfOutlineNode> onOpenNode;

  @override
  Widget build(BuildContext context) {
    final entries = <_OutlineEntry>[];
    for (final node in outline) {
      _appendOutlineNode(entries, node, 0);
    }
    return SizedBox(
      width: 260,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AleraTokens.surface,
          border: Border(right: BorderSide(color: AleraTokens.borderSubtle)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: AleraTokens.sidebarHeaderHeight,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AleraTokens.space8,
                  right: AleraTokens.space4,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Outline',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ),
                    AleraIconButton(
                      tooltip: 'Hide outline',
                      icon: Icons.close,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                  ? const _PdfViewerMessage(message: 'No outline')
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _PdfOutlineRow(
                          entry: entry,
                          onTap: entry.node.dest == null
                              ? null
                              : () => onOpenNode(entry.node),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _appendOutlineNode(
    List<_OutlineEntry> entries,
    PdfOutlineNode node,
    int depth,
  ) {
    entries.add(_OutlineEntry(node: node, depth: depth));
    for (final child in node.children) {
      _appendOutlineNode(entries, child, depth + 1);
    }
  }
}

class _PdfOutlineRow extends StatelessWidget {
  const _PdfOutlineRow({required this.entry, required this.onTap});

  final _OutlineEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      mouseCursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AleraTokens.space8 + entry.depth * AleraTokens.space16,
          AleraTokens.space6,
          AleraTokens.space8,
          AleraTokens.space6,
        ),
        child: Text(
          entry.node.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: onTap == null
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
        ),
      ),
    );
  }
}

class _OutlineEntry {
  const _OutlineEntry({required this.node, required this.depth});

  final PdfOutlineNode node;
  final int depth;
}

@visibleForTesting
Key workspacePdfViewerCacheKeyForTesting(ResolvedWorkspaceFile file) {
  return ValueKey<String>('${file.path}:${file.modifiedMicros}:${file.length}');
}

class _PdfViewerMessage extends StatelessWidget {
  const _PdfViewerMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}
