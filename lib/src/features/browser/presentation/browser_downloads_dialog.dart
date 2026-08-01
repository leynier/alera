import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:flutter/material.dart';

class BrowserDownloadsDialog extends StatelessWidget {
  const BrowserDownloadsDialog({
    super.key,
    required this.downloads,
    this.onCancel,
    required this.onOpen,
    required this.onReveal,
  });

  final List<BrowserDownload> downloads;
  final ValueChanged<BrowserDownload>? onCancel;
  final ValueChanged<BrowserDownload> onOpen;
  final ValueChanged<BrowserDownload> onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.download,
                  size: AleraTokens.space20,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text('Downloads', style: theme.textTheme.titleMedium),
                ),
                AleraIconButton(
                  tooltip: 'Close',
                  icon: AleraIcons.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            Expanded(
              child: downloads.isEmpty
                  ? const AleraEmptyState(
                      icon: AleraIcons.download,
                      title: 'No downloads yet',
                      message:
                          'Files downloaded from this tab will appear here.',
                    )
                  : ListView.separated(
                      itemCount: downloads.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: AleraTokens.dividerExtent,
                        color: AleraTokens.borderSubtle,
                      ),
                      itemBuilder: (context, index) {
                        final download = downloads[index];
                        return _BrowserDownloadRow(
                          download: download,
                          onCancel: onCancel == null
                              ? null
                              : () => onCancel!(download),
                          onOpen: () => onOpen(download),
                          onReveal: () => onReveal(download),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserDownloadRow extends StatelessWidget {
  const _BrowserDownloadRow({
    required this.download,
    this.onCancel,
    required this.onOpen,
    required this.onReveal,
  });

  final BrowserDownload download;
  final VoidCallback? onCancel;
  final VoidCallback onOpen;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = download.status == BrowserDownloadStatus.completed;
    final canOpen = completed && download.savePath?.trim().isNotEmpty == true;
    final cancellable =
        download.status == BrowserDownloadStatus.pending ||
        download.status == BrowserDownloadStatus.downloading;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            _statusIcon(download.status),
            size: AleraTokens.space20,
            color: _statusColor(download.status),
          ),
          const SizedBox(width: AleraTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  download.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AleraTokens.foreground,
                  ),
                ),
                const SizedBox(height: AleraTokens.space4),
                Text(
                  _statusLabel(download),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                if (download.progress case final progress?) ...<Widget>[
                  const SizedBox(height: AleraTokens.space6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: AleraTokens.space4,
                      color: AleraTokens.info,
                      backgroundColor: AleraTokens.surfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          if (cancellable && onCancel != null)
            AleraIconButton(
              tooltip: 'Cancel Download',
              icon: AleraIcons.cancel,
              onPressed: onCancel,
            ),
          if (canOpen) ...<Widget>[
            AleraIconButton(
              tooltip: 'Open File',
              icon: AleraIcons.external,
              onPressed: onOpen,
            ),
            AleraIconButton(
              tooltip: 'Show In Folder',
              icon: AleraIcons.folderOpen,
              onPressed: onReveal,
            ),
          ],
        ],
      ),
    );
  }
}

IconData _statusIcon(BrowserDownloadStatus status) {
  return switch (status) {
    BrowserDownloadStatus.pending ||
    BrowserDownloadStatus.downloading => AleraIcons.downloading,
    BrowserDownloadStatus.completed => AleraIcons.success,
    BrowserDownloadStatus.cancelled => AleraIcons.cancel,
    BrowserDownloadStatus.failed => AleraIcons.error,
  };
}

Color _statusColor(BrowserDownloadStatus status) {
  return switch (status) {
    BrowserDownloadStatus.pending ||
    BrowserDownloadStatus.downloading => AleraTokens.info,
    BrowserDownloadStatus.completed => AleraTokens.success,
    BrowserDownloadStatus.cancelled => AleraTokens.foregroundFaint,
    BrowserDownloadStatus.failed => AleraTokens.error,
  };
}

String _statusLabel(BrowserDownload download) {
  return switch (download.status) {
    BrowserDownloadStatus.pending => 'Preparing download',
    BrowserDownloadStatus.downloading =>
      '${_formatBytes(download.receivedBytes)}${download.totalBytes == null ? '' : ' of ${_formatBytes(download.totalBytes!)}'}',
    BrowserDownloadStatus.completed => 'Download complete',
    BrowserDownloadStatus.cancelled => 'Download cancelled',
    BrowserDownloadStatus.failed =>
      download.error?.trim().isNotEmpty == true
          ? download.error!
          : 'Download failed',
  };
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kib = bytes / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(kib >= 10 ? 0 : 1)} KB';
  }
  final mib = kib / 1024;
  if (mib < 1024) {
    return '${mib.toStringAsFixed(mib >= 10 ? 0 : 1)} MB';
  }
  final gib = mib / 1024;
  return '${gib.toStringAsFixed(gib >= 10 ? 0 : 1)} GB';
}
