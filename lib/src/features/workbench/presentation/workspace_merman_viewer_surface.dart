import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_editor_surface.dart';
import 'package:alera/src/rust/api/merman_viewer.dart' as merman_native;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WorkspaceMermanViewerSurface extends ConsumerStatefulWidget {
  const WorkspaceMermanViewerSurface({
    super.key,
    required this.workspace,
    required this.tab,
    required this.autofocus,
    required this.onOpenEditor,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final bool autofocus;
  final ValueChanged<String> onOpenEditor;

  @override
  ConsumerState<WorkspaceMermanViewerSurface> createState() =>
      _WorkspaceMermanViewerSurfaceState();
}

class _WorkspaceMermanViewerSurfaceState
    extends ConsumerState<WorkspaceMermanViewerSurface> {
  late final WorkspaceFileService _workspaceFiles;
  late final FocusNode _focusNode;
  merman_native.MermanWorkspaceRender? _rendered;
  Object? _loadError;
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _workspaceFiles = ref.read(workspaceFileServiceProvider);
    unawaited(_load());
    if (widget.autofocus) {
      _requestFocusNextFrame();
    }
  }

  @override
  void didUpdateWidget(covariant WorkspaceMermanViewerSurface oldWidget) {
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
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      return const _MermanViewerMessage(message: 'This tab has no diagram.');
    }

    final displayPath = workspaceEditorDisplayPath(
      workspace: widget.workspace,
      filePath: filePath,
    );
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_loadError case final error?) {
      content = _MermanViewerMessage(message: _messageFor(error));
    } else if (_rendered case final rendered?) {
      content = _MermanViewerCanvas(rendered: rendered);
    } else {
      content = const _MermanViewerMessage(message: 'Diagram cannot be opened');
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
              _MermanViewerFileBar(
                path: displayPath,
                loading: _loading,
                onOpenEditor: () => widget.onOpenEditor(filePath),
                onRefresh: _loading ? null : () => unawaited(_load()),
              ),
              const Divider(height: 1, color: AleraTokens.borderSubtle),
              Expanded(child: content),
            ],
          ),
        ),
      ),
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
    final requestedWorkspacePath = widget.workspace.path;
    final filePath = widget.tab.filePath;
    if (filePath == null) {
      setState(() {
        _rendered = null;
        _loadError = null;
        _loading = false;
      });
      return;
    }
    final requestedFilePath = filePath;
    setState(() {
      _rendered = null;
      _loadError = null;
      _loading = true;
    });
    try {
      final rendered = await _workspaceFiles.renderMermanWorkspaceFile(
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
        _rendered = rendered;
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
        _rendered = null;
        _loadError = error;
        _loading = false;
      });
    }
  }

  bool _isCurrentLoad(int generation, String workspacePath, String filePath) {
    return mounted &&
        _loadGeneration == generation &&
        widget.workspace.path == workspacePath &&
        widget.tab.filePath == filePath;
  }

  String _messageFor(Object error) {
    if (error is merman_native.MermanViewerError) {
      return switch (error.kind) {
        merman_native.MermanViewerErrorKind.notFound => 'Diagram not found',
        merman_native.MermanViewerErrorKind.outsideWorkspace =>
          'Diagram is outside the workspace',
        merman_native.MermanViewerErrorKind.invalidPath =>
          'Diagram path is invalid',
        merman_native.MermanViewerErrorKind.unsupported =>
          'Diagram cannot be opened',
        merman_native.MermanViewerErrorKind.render =>
          'Diagram cannot be rendered',
        merman_native.MermanViewerErrorKind.io => 'Diagram cannot be opened',
      };
    }
    return 'Diagram cannot be opened';
  }
}

class _MermanViewerFileBar extends StatelessWidget {
  const _MermanViewerFileBar({
    required this.path,
    required this.loading,
    required this.onOpenEditor,
    required this.onRefresh,
  });

  final String path;
  final bool loading;
  final VoidCallback onOpenEditor;
  final VoidCallback? onRefresh;

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
            const SizedBox(width: AleraTokens.space8),
            AleraIconButton(
              tooltip: 'Open editor',
              icon: Icons.edit_outlined,
              onPressed: onOpenEditor,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: loading ? 'Loading preview' : 'Refresh',
              icon: loading ? Icons.hourglass_empty : Icons.refresh,
              onPressed: onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}

class _MermanViewerCanvas extends StatelessWidget {
  const _MermanViewerCanvas({required this.rendered});

  final merman_native.MermanWorkspaceRender rendered;

  @override
  Widget build(BuildContext context) {
    final svg = prepareMermanSvgForFlutterSvg(rendered.svg);
    return ClipRect(
      child: InteractiveViewer(
        minScale: 0.25,
        maxScale: 8,
        boundaryMargin: const EdgeInsets.all(AleraTokens.space48),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AleraTokens.space24),
            child: SvgPicture.string(
              svg,
              key: ValueKey<String>(
                '${rendered.contentToken}:${rendered.modifiedMillis}:${rendered.size}',
              ),
              fit: BoxFit.contain,
              colorMapper: const _MermanSvgColorMapper(),
              placeholderBuilder: (_) =>
                  const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _MermanSvgColorMapper extends ColorMapper {
  const _MermanSvgColorMapper();

  static const Color _black = Color(0xFF000000);
  static const Color _mermanText = Color(0xFF333333);

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    final element = elementName.toLowerCase();
    if (color == _mermanText &&
        (element == 'text' || element == 'tspan' || element == 'span')) {
      return AleraTokens.foreground;
    }
    if (color != _black) {
      return color;
    }
    final attribute = attributeName.toLowerCase();
    if (element == 'text' || element == 'tspan') {
      return AleraTokens.foreground;
    }
    if (attribute == 'stroke') {
      return AleraTokens.foregroundMuted;
    }
    if (element == 'rect' ||
        element == 'circle' ||
        element == 'ellipse' ||
        element == 'polygon') {
      return AleraTokens.surfaceElevated;
    }
    if (element == 'path' && attribute == 'fill') {
      return AleraTokens.foregroundMuted;
    }
    return color;
  }
}

@visibleForTesting
String prepareMermanSvgForFlutterSvg(String svg) {
  var next = svg
      .replaceAll('fill="#333"', 'fill="${_svgColor(AleraTokens.foreground)}"')
      .replaceAll(
        'fill="#333333"',
        'fill="${_svgColor(AleraTokens.foreground)}"',
      )
      .replaceAll(
        'stroke="#333333"',
        'stroke="${_svgColor(AleraTokens.foregroundMuted)}"',
      );
  next = _withMermanClassAttributes(
    next,
    tagName: 'rect',
    className: 'basic label-container',
    fill: _svgColor(AleraTokens.surfaceElevated),
    stroke: _svgColor(AleraTokens.border),
  );
  next = _withMermanClassAttributes(
    next,
    tagName: 'path',
    className: 'flowchart-link',
    fill: 'none',
    stroke: _svgColor(AleraTokens.foregroundMuted),
  );
  next = _withMermanClassAttributes(
    next,
    tagName: 'path',
    className: 'arrowMarkerPath',
    fill: _svgColor(AleraTokens.foregroundMuted),
    stroke: _svgColor(AleraTokens.foregroundMuted),
  );
  next = _withMermanClassAttributes(
    next,
    tagName: 'polygon',
    className: 'arrowMarkerPath',
    fill: _svgColor(AleraTokens.foregroundMuted),
    stroke: _svgColor(AleraTokens.foregroundMuted),
  );
  next = _withMermanClassAttributes(
    next,
    tagName: 'circle',
    className: 'arrowMarkerPath',
    fill: _svgColor(AleraTokens.foregroundMuted),
    stroke: _svgColor(AleraTokens.foregroundMuted),
  );
  return next;
}

String _withMermanClassAttributes(
  String svg, {
  required String tagName,
  required String className,
  String? fill,
  String? stroke,
}) {
  final escapedTag = RegExp.escape(tagName);
  final escapedClass = RegExp.escape(className);
  final pattern = RegExp(
    '<$escapedTag\\b(?=[^>]*class="[^"]*\\b$escapedClass\\b[^"]*")[^>]*\\/?>',
  );
  return svg.replaceAllMapped(pattern, (match) {
    var tag = match.group(0)!;
    if (fill != null && !RegExp(r'\sfill=').hasMatch(tag)) {
      tag = _insertSvgAttribute(tag, 'fill', fill);
    }
    if (stroke != null && !RegExp(r'\sstroke=').hasMatch(tag)) {
      tag = _insertSvgAttribute(tag, 'stroke', stroke);
    }
    return tag;
  });
}

String _insertSvgAttribute(String tag, String name, String value) {
  final insertAt = tag.endsWith('/>') ? tag.length - 2 : tag.length - 1;
  return '${tag.substring(0, insertAt)} $name="$value"${tag.substring(insertAt)}';
}

String _svgColor(Color color) {
  final rgb = color.toARGB32() & 0x00ffffff;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class _MermanViewerMessage extends StatelessWidget {
  const _MermanViewerMessage({required this.message});

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
