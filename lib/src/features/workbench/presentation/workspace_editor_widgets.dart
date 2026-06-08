part of 'workspace_editor_surface.dart';

class _EditorFileBar extends StatelessWidget {
  const _EditorFileBar({
    required this.path,
    required this.dirty,
    required this.saving,
    required this.onViewDiff,
    required this.onSave,
    required this.onDiscard,
    required this.onOpenPreview,
  });

  final String path;
  final bool dirty;
  final bool saving;
  final VoidCallback? onViewDiff;
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;
  final VoidCallback? onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = dirty ? AleraTokens.foreground : AleraTokens.foregroundMuted;
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
              fallbackColor: color,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            if (onOpenPreview != null) ...<Widget>[
              AleraIconButton(
                tooltip: 'Open preview',
                icon: AleraIcons.visible,
                onPressed: onOpenPreview,
                iconColor: color,
              ),
              const SizedBox(width: AleraTokens.space2),
            ],
            AleraIconButton(
              tooltip: 'View diff',
              icon: AleraIcons.diff,
              onPressed: onViewDiff,
              iconColor: color,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: saving ? 'Saving file' : 'Save file',
              icon: saving ? AleraIcons.loading : AleraIcons.save,
              onPressed: onSave,
              iconColor: color,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Discard changes',
              icon: AleraIcons.restore,
              onPressed: onDiscard,
              iconColor: color,
            ),
            if (onOpenPreview != null) ...<Widget>[
              const SizedBox(width: AleraTokens.space2),
              AleraIconButton(
                tooltip: 'Open preview',
                icon: AleraIcons.preview,
                onPressed: onOpenPreview,
                iconColor: color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
