part of 'workspace_git_diff_panel.dart';

String _terminalPathForGitEntry(String workspacePath, String relativePath) {
  return terminalAbsolutePath(
    rootPath: workspacePath,
    relativePath: relativePath,
  );
}

class _GitPathDragRegion extends StatelessWidget {
  const _GitPathDragRegion({
    required this.absolutePath,
    required this.label,
    required this.isDirectory,
    required this.child,
  });

  final String absolutePath;
  final String label;
  final bool isDirectory;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TerminalPathLongPressDraggable<TerminalPathDragData>(
      data: TerminalPathDragData(paths: <String>[absolutePath]),
      feedback: _GitPathDragFeedback(label: label, isDirectory: isDirectory),
      child: child,
    );
  }
}

class _GitPathDragFeedback extends StatelessWidget {
  const _GitPathDragFeedback({required this.label, required this.isDirectory});

  final String label;
  final bool isDirectory;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AleraTokens.surfaceElevated,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.sidebarDefaultWidth,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space6,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: AleraTokens.border),
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: AleraTokens.shadowSoft,
              blurRadius: AleraTokens.space12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AleraFileIcon(
              pathOrName: label,
              kind: isDirectory
                  ? AleraFileIconKind.folder
                  : AleraFileIconKind.file,
              size: AleraTokens.space16,
            ),
            const SizedBox(width: AleraTokens.space8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AleraTokens.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GitDiffBaseRow extends StatelessWidget {
  const _GitDiffBaseRow({
    required this.depth,
    required this.child,
    required this.onTap,
  });

  final int depth;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: AleraTokens.space8 + (depth * AleraTokens.space12),
            right: AleraTokens.space8,
            top: AleraTokens.space4,
            bottom: AleraTokens.space4,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LineStats extends StatelessWidget {
  const _LineStats({required this.added, required this.removed});

  final int? added;
  final int? removed;

  @override
  Widget build(BuildContext context) {
    final visibleAdded = added != null && added! > 0 ? added : null;
    final visibleRemoved = removed != null && removed! > 0 ? removed : null;
    if (visibleAdded == null && visibleRemoved == null) {
      return const SizedBox(width: 64);
    }
    final style = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      width: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (visibleAdded case final added?)
            Flexible(
              child: Text(
                '+$added',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(color: AleraTokens.success),
              ),
            ),
          if (visibleRemoved case final removed?) ...<Widget>[
            const SizedBox(width: AleraTokens.space4),
            Flexible(
              child: Text(
                '-$removed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(color: AleraTokens.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GitStatusLabel extends StatelessWidget {
  const _GitStatusLabel({required this.status});

  final GitChangeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      GitChangeStatus.added => ('A', AleraTokens.success),
      GitChangeStatus.untracked => ('U', AleraTokens.success),
      GitChangeStatus.deleted => ('D', AleraTokens.error),
      GitChangeStatus.renamed => ('R', AleraTokens.warning),
      GitChangeStatus.copied => ('C', AleraTokens.warning),
      GitChangeStatus.modified => ('M', AleraTokens.warning),
    };
    return SizedBox(
      width: 12,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
