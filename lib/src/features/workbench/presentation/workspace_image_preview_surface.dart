import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_image_decoding.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_editor_surface.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const WorkspaceImagePreviewSurface({
  super.key,
  required final Workspace workspace,
  required final WorkspaceTabRecord tab,
  required final bool autofocus,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<WorkspaceImagePreviewSurface> createState() =>
      _WorkspaceImagePreviewSurfaceState();
}

class _WorkspaceImagePreviewSurfaceState
    extends ConsumerState<WorkspaceImagePreviewSurface> {
  late final WorkspaceFileService _workspaceFiles;
  late final FocusNode _focusNode;
  _ResolvedPreviewImage? _resolvedImage;
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
  void didUpdateWidget(covariant WorkspaceImagePreviewSurface oldWidget) {
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
      return const _ImagePreviewMessage(message: 'This tab has no image.');
    }

    final displayPath = workspaceEditorDisplayPath(
      workspace: widget.workspace,
      filePath: filePath,
    );
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_loadError case final error?) {
      content = _ImagePreviewMessage(message: _messageFor(error));
    } else if (_resolvedImage case final resolvedImage?) {
      content = _ImagePreviewCanvas(resolvedImage: resolvedImage);
    } else {
      content = const _ImagePreviewMessage(message: 'Image cannot be opened');
    }

    return Listener(
      onPointerDown: (_) => _focusNode.requestFocus(),
      child: Focus(
        focusNode: _focusNode,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AleraTokens.bg),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              _ImagePreviewFileBar(path: displayPath),
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
        _resolvedImage = null;
        _loadError = null;
        _loading = false;
      });
      return;
    }
    final requestedFilePath = filePath;
    setState(() {
      _resolvedImage = null;
      _loadError = null;
      _loading = true;
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
      final resolvedImage = await _resolvePreviewImage(
        file: resolvedFile,
        openedPath: requestedFilePath,
      );
      if (!_isCurrentLoad(
        generation,
        requestedWorkspacePath,
        requestedFilePath,
      )) {
        return;
      }
      await resolvedImage.provider.evict();
      if (!_isCurrentLoad(
        generation,
        requestedWorkspacePath,
        requestedFilePath,
      )) {
        return;
      }
      setState(() {
        _resolvedImage = resolvedImage;
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
        _resolvedImage = null;
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<_ResolvedPreviewImage> _resolvePreviewImage({
    required ResolvedWorkspaceFile file,
    required String openedPath,
  }) async {
    if (workspaceImagePreviewUsesIcoDecoderForTesting(openedPath)) {
      final bytes = await File(file.path).readAsBytes();
      final pngBytes = await compute(decodeWorkspaceIcoToPngBytes, bytes);
      return _ResolvedPreviewImage(file: file, provider: MemoryImage(pngBytes));
    }
    return _ResolvedPreviewImage(
      file: file,
      provider: FileImage(File(file.path)),
    );
  }

  bool _isCurrentLoad(int generation, String workspacePath, String filePath) {
    return mounted &&
        _loadGeneration == generation &&
        widget.workspace.path == workspacePath &&
        widget.tab.filePath == filePath;
  }

  String _messageFor(Object error) {
    if (error is native.WorkspaceFileError) {
      return switch (error.kind) {
        native.WorkspaceFileErrorKind.notFound => 'Image not found',
        native.WorkspaceFileErrorKind.outsideWorkspace =>
          'Image is outside the workspace',
        native.WorkspaceFileErrorKind.invalidPath => 'Image path is invalid',
        _ => 'Image cannot be opened',
      };
    }
    return 'Image cannot be opened';
  }
}

class const _ImagePreviewFileBar({required final String path})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            AleraFileIcon(pathOrName: path, kind: .file, size: 16),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: .ellipsis,
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

class const _ImagePreviewCanvas({
  required final _ResolvedPreviewImage resolvedImage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: InteractiveViewer(
        minScale: 0.25,
        maxScale: 8,
        boundaryMargin: const .all(AleraTokens.space48),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AleraTokens.space24),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Image(
                key: workspaceImagePreviewCacheKeyForTesting(
                  resolvedImage.file,
                ),
                image: resolvedImage.provider,
                fit: .contain,
                errorBuilder: (_, _, _) => const _ImagePreviewMessage(
                  message: 'Image cannot be opened',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Key workspaceImagePreviewCacheKeyForTesting(ResolvedWorkspaceFile file) {
  return ValueKey<String>('${file.path}:${file.modifiedMicros}:${file.length}');
}

@visibleForTesting
bool workspaceImagePreviewUsesIcoDecoderForTesting(String openedPath) {
  return isWorkspaceIcoFilePath(openedPath);
}

class const _ResolvedPreviewImage({
  required final ResolvedWorkspaceFile file,
  required final ImageProvider<Object> provider,
});

@visibleForTesting
Uint8List workspaceImagePreviewDecodeIcoToPngBytesForTesting(Uint8List bytes) {
  return decodeWorkspaceIcoToPngBytes(bytes);
}

class const _ImagePreviewMessage({required final String message})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: .center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}
