import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:alera/src/features/workbench/application/workspace_image_decoding.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef WorkspaceGitDiffImageSides = ({
  Uint8List? oldBytes,
  Uint8List? newBytes,
});

/// Before/after preview for a binary diff entry whose path is an image.
class WorkspaceGitDiffImageRow extends ConsumerStatefulWidget {
  const WorkspaceGitDiffImageRow({
    super.key,
    required this.file,
    required this.sourcePath,
    this.commitOid,
    this.parentOid,
  });

  final GitDiffFile file;

  /// Absolute path of the source-control scope the diff was loaded from.
  final String sourcePath;

  /// Set when the diff came from a commit instead of the working tree.
  final String? commitOid;
  final String? parentOid;

  @override
  ConsumerState<WorkspaceGitDiffImageRow> createState() =>
      _WorkspaceGitDiffImageRowState();
}

class _WorkspaceGitDiffImageRowState
    extends ConsumerState<WorkspaceGitDiffImageRow> {
  late Future<WorkspaceGitDiffImageSides> _sides;

  @override
  void initState() {
    super.initState();
    _sides = _load();
  }

  @override
  void didUpdateWidget(covariant WorkspaceGitDiffImageRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.file.area != widget.file.area ||
        oldWidget.sourcePath != widget.sourcePath ||
        oldWidget.commitOid != widget.commitOid) {
      _sides = _load();
    }
  }

  Future<WorkspaceGitDiffImageSides> _load() async {
    final results = await Future.wait(<Future<Uint8List?>>[
      _loadSide(oldSide: true),
      _loadSide(oldSide: false),
    ]);
    return (oldBytes: results[0], newBytes: results[1]);
  }

  Future<Uint8List?> _loadSide({required bool oldSide}) async {
    try {
      final bytes = await ref
          .read(gitBackendProvider)
          .diffBlobBytes(
            path: widget.sourcePath,
            filePath: widget.file.path,
            oldPath: widget.file.oldPath,
            area: widget.commitOid == null ? widget.file.area : null,
            commitOid: widget.commitOid,
            parentOid: widget.parentOid,
            oldSide: oldSide,
          );
      if (bytes == null) {
        return null;
      }
      final sidePath = oldSide
          ? (widget.file.oldPath ?? widget.file.path)
          : widget.file.path;
      if (isWorkspaceIcoFilePath(sidePath)) {
        return compute(decodeWorkspaceIcoToPngBytes, bytes);
      }
      return bytes;
    } on GitException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkspaceGitDiffImageSides>(
      future: _sides,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: _WorkspaceGitDiffImageCell.height,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final sides =
            snapshot.data ??
            (oldBytes: null as Uint8List?, newBytes: null as Uint8List?);
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space12,
            vertical: AleraTokens.space8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _WorkspaceGitDiffImageCell(
                  label: 'Before',
                  bytes: sides.oldBytes,
                  missingPlaceholder: _oldPlaceholder,
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: _WorkspaceGitDiffImageCell(
                  label: 'After',
                  bytes: sides.newBytes,
                  missingPlaceholder: _newPlaceholder,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String get _oldPlaceholder {
    return switch (widget.file.status) {
      GitChangeStatus.added || GitChangeStatus.untracked => 'Added',
      _ => 'Preview Unavailable',
    };
  }

  String get _newPlaceholder {
    return widget.file.status == GitChangeStatus.deleted
        ? 'Deleted'
        : 'Preview Unavailable';
  }
}

class _WorkspaceGitDiffImageCell extends StatelessWidget {
  const _WorkspaceGitDiffImageCell({
    required this.label,
    required this.bytes,
    required this.missingPlaceholder,
  });

  static const double height = 180;

  final String label;
  final Uint8List? bytes;
  final String missingPlaceholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = this.bytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          bytes == null ? label : '$label · ${_formatBytes(bytes.length)}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundFaint,
          ),
        ),
        const SizedBox(height: AleraTokens.space4),
        Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AleraTokens.surfaceElevated,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: bytes == null
              ? Center(
                  child: Text(
                    missingPlaceholder,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundFaint,
                    ),
                  ),
                )
              : Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Text(
                      'Preview Unavailable',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundFaint,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  String _formatBytes(int length) {
    if (length < 1024) {
      return '$length B';
    }
    if (length < 1024 * 1024) {
      return '${(length / 1024).toStringAsFixed(1)} KB';
    }
    return '${(length / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
