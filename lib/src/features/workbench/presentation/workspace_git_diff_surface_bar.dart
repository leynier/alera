part of 'workspace_git_diff_surface.dart';

class _GitDiffBar extends StatelessWidget {
  const _GitDiffBar({
    required this.title,
    required this.filePath,
    required this.onRefresh,
    required this.onOpenFile,
    required this.aiTextEnabled,
    required this.readingDiffReady,
    required this.showingReadingDiff,
    required this.readingDiffBusy,
    required this.onGenerateReadingDiff,
    required this.onRegenerateReadingDiff,
    required this.onCancelReadingDiff,
    required this.onToggleReadingDiff,
  });

  final String title;
  final String? filePath;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenFile;
  final bool aiTextEnabled;
  final bool readingDiffReady;
  final bool showingReadingDiff;
  final bool readingDiffBusy;
  final VoidCallback? onGenerateReadingDiff;
  final VoidCallback? onRegenerateReadingDiff;
  final VoidCallback onCancelReadingDiff;
  final VoidCallback? onToggleReadingDiff;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            AleraFileIcon(
              pathOrName: filePath ?? title,
              kind: AleraFileIconKind.file,
              size: 16,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            if (aiTextEnabled) ...<Widget>[
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
              if (readingDiffReady && !readingDiffBusy) ...<Widget>[
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
