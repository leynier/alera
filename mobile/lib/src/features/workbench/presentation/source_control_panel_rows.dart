part of 'source_control_panel.dart';

class const _ChangeRow({
  required final MobileGitChange change,
  required final VoidCallback onTap,
  final int depth = 0,
  final bool showParent = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = workspaceFileBaseName(change.path);
    final parent = showParent ? workspaceFileParentLabel(change.path) : null;
    final (letter, color) = _statusMark(change.status);
    return Tooltip(
      message: change.path,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AleraTokens.minTapTarget,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AleraTokens.space16 + depth * AleraTokens.space16,
              AleraTokens.space8,
              AleraTokens.space16,
              AleraTokens.space8,
            ),
            child: Row(
              children: <Widget>[
                AleraFileIcon(pathOrName: change.path, kind: .file),
                const SizedBox(width: AleraTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (parent != null)
                        Text(
                          parent,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                SizedBox(
                  width: AleraTokens.space16,
                  child: Text(
                    letter,
                    textAlign: .center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: .w600,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                _LineStats(added: change.added, removed: change.removed),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _LineStats({required final int? added, required final int? removed})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final visibleAdded = added != null && added! > 0 ? added : null;
    final visibleRemoved = removed != null && removed! > 0 ? removed : null;
    if (visibleAdded == null && visibleRemoved == null) {
      return const SizedBox.shrink();
    }
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        if (visibleAdded case final added?)
          Text('+$added', style: style?.copyWith(color: AleraTokens.success)),
        if (visibleRemoved case final removed?) ...<Widget>[
          if (visibleAdded != null) const SizedBox(width: AleraTokens.space6),
          Text('-$removed', style: style?.copyWith(color: AleraTokens.error)),
        ],
      ],
    );
  }
}

(String, Color) _statusMark(String status) {
  return switch (status) {
    'added' => ('A', AleraTokens.success),
    'untracked' => ('U', AleraTokens.success),
    'deleted' => ('D', AleraTokens.error),
    'renamed' => ('R', AleraTokens.warning),
    'copied' => ('C', AleraTokens.warning),
    'modified' => ('M', AleraTokens.warning),
    _ => (
      status.isEmpty ? 'M' : status[0].toUpperCase(),
      AleraTokens.foregroundMuted,
    ),
  };
}

class const _DirectoryRow({
  required final String name,
  required final int depth,
  required final int fileCount,
  required final bool collapsed,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AleraTokens.minTapTarget),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AleraTokens.space16 + depth * AleraTokens.space16,
            0,
            AleraTokens.space16,
            0,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
                size: 16,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space4),
              Icon(
                collapsed ? AleraIcons.folder : AleraIcons.folderOpen,
                size: 16,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                '$fileCount',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _SectionRow({
  required final SourceControlSection section,
  required final bool collapsed,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AleraSectionHeader(
        label: section.label,
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space16,
          AleraTokens.space16,
          AleraTokens.space16,
          AleraTokens.space4,
        ),
        trailing: Row(
          mainAxisSize: .min,
          children: <Widget>[
            Text(
              '${section.entries.length}',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: AleraTokens.foregroundFaint),
            ),
            const SizedBox(width: AleraTokens.space4),
            Icon(
              collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
              size: 16,
              color: AleraTokens.foregroundMuted,
            ),
          ],
        ),
      ),
    );
  }
}
