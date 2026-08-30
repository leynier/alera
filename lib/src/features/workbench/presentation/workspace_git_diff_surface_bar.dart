part of 'workspace_git_diff_surface.dart';

class const _GitDiffBar({
  required final String title,
  required final String? filePath,
  required final VoidCallback onRefresh,
  required final VoidCallback? onOpenFile,
  required final bool aiAssistEnabled,
  required final bool readingDiffReady,
  required final bool showingReadingDiff,
  required final bool readingDiffBusy,
  required final VoidCallback? onGenerateReadingDiff,
  required final VoidCallback? onRegenerateReadingDiff,
  required final VoidCallback onCancelReadingDiff,
  required final VoidCallback? onToggleReadingDiff,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            AleraFileIcon(pathOrName: filePath ?? title, kind: .file, size: 16),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: .ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            if (aiAssistEnabled ||
                readingDiffReady ||
                readingDiffBusy) ...<Widget>[
              AleraIconButton(
                tooltip: readingDiffBusy
                    ? 'Cancel Reading Diff'
                    : readingDiffReady
                    ? showingReadingDiff
                          ? 'Show Original Diff'
                          : 'Show Reading Diff'
                    : 'Generate Reading Diff',
                icon: readingDiffBusy
                    ? AleraIcons.cancel
                    : showingReadingDiff
                    ? AleraIcons.diff
                    : AleraIcons.ai,
                onPressed: readingDiffBusy
                    ? onCancelReadingDiff
                    : readingDiffReady
                    ? onToggleReadingDiff
                    : onGenerateReadingDiff,
              ),
              if (aiAssistEnabled &&
                  readingDiffReady &&
                  !readingDiffBusy) ...<Widget>[
                const SizedBox(width: AleraTokens.space2),
                AleraIconButton(
                  tooltip: 'Regenerate Reading Diff',
                  icon: AleraIcons.refresh,
                  onPressed: onRegenerateReadingDiff,
                ),
              ],
              const SizedBox(width: AleraTokens.space2),
            ],
            AleraIconButton(
              tooltip: onOpenFile == null
                  ? 'File is not available in working tree'
                  : 'Open file',
              icon: AleraIcons.external,
              onPressed: onOpenFile,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Refresh',
              icon: AleraIcons.refresh,
              onPressed: onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}
