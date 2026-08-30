part of 'workspace_editor_surface.dart';

@visibleForTesting
String workspaceEditorCodeForgeKey({
  required String tabId,
  required String filePath,
  required String themeName,
}) {
  return 'workspace-editor-$tabId-$filePath-$themeName';
}

class const _EditorFileBar({
  required final String path,
  required final bool dirty,
  required final bool saving,
  required final VoidCallback? onViewDiff,
  required final VoidCallback? onSave,
  required final VoidCallback? onDiscard,
  required final VoidCallback? onOpenPreview,
}) extends StatelessWidget {
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
              kind: .file,
              size: 16,
              fallbackColor: color,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            AleraIconButton(
              tooltip: 'View Diff',
              icon: AleraIcons.diff,
              onPressed: onViewDiff,
              iconColor: color,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: saving ? 'Saving File' : 'Save File',
              icon: saving ? AleraIcons.loading : AleraIcons.save,
              onPressed: onSave,
              iconColor: color,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Discard Changes',
              icon: AleraIcons.restore,
              onPressed: onDiscard,
              iconColor: color,
            ),
            if (onOpenPreview != null) ...<Widget>[
              const SizedBox(width: AleraTokens.space2),
              AleraIconButton(
                tooltip: 'Open Preview',
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
