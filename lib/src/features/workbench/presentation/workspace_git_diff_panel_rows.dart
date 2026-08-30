part of 'workspace_git_diff_panel.dart';

String _terminalPathForGitEntry(String workspacePath, String relativePath) {
  return terminalAbsolutePath(
    rootPath: workspacePath,
    relativePath: relativePath,
  );
}

class const _GitPathDragRegion({
  required final String absolutePath,
  required final String label,
  required final bool isDirectory,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TerminalPathDraggable<TerminalPathDragData>(
      data: TerminalPathDragData(paths: <String>[absolutePath]),
      feedback: _GitPathDragFeedback(label: label, isDirectory: isDirectory),
      child: child,
    );
  }
}

class const _GitPathDragFeedback({
  required final String label,
  required final bool isDirectory,
}) extends StatelessWidget {
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
          mainAxisSize: .min,
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
                overflow: .ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _GitDiffBaseRow({
  required final int depth,
  required final Widget child,
  required final VoidCallback onTap,
  final GestureTapDownCallback? onSecondaryTapDown,
  final GestureLongPressStartCallback? onLongPressStart,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: .translucent,
        onTap: onTap,
        onSecondaryTapDown: onSecondaryTapDown,
        onLongPressStart: onLongPressStart,
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

class const _LineStats({required final int? added, required final int? removed})
    extends StatelessWidget {
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
        mainAxisAlignment: .end,
        children: <Widget>[
          if (visibleAdded case final added?)
            Flexible(
              child: Text(
                '+$added',
                maxLines: 1,
                overflow: .ellipsis,
                style: style?.copyWith(color: AleraTokens.success),
              ),
            ),
          if (visibleRemoved case final removed?) ...<Widget>[
            const SizedBox(width: AleraTokens.space4),
            Flexible(
              child: Text(
                '-$removed',
                maxLines: 1,
                overflow: .ellipsis,
                style: style?.copyWith(color: AleraTokens.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class const _GitStatusLabel({
  required final GitChangeStatus status,
  final GitChangeArea? area,
  this.showAreaMarker = false,
}) extends StatelessWidget {
  /// When true, append a small staged/unstaged marker next to the letter so
  /// files can share one list without area section headers.
  final bool showAreaMarker;

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
    final areaMarker = showAreaMarker ? _areaMarker(area) : null;
    final tooltip = showAreaMarker ? _areaTooltip(area) : null;
    final content = Row(
      mainAxisSize: .min,
      children: <Widget>[
        SizedBox(
          width: 12,
          child: Text(
            label,
            textAlign: .center,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color),
          ),
        ),
        if (areaMarker != null)
          SizedBox(
            width: 10,
            child: Text(
              areaMarker,
              textAlign: .left,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: area == GitChangeArea.staged
                    ? AleraTokens.success
                    : AleraTokens.foregroundFaint,
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
    if (tooltip == null) {
      return content;
    }
    return Tooltip(message: tooltip, child: content);
  }

  static String? _areaMarker(GitChangeArea? area) {
    return switch (area) {
      GitChangeArea.staged => 'S',
      GitChangeArea.unstaged => '·',
      GitChangeArea.untracked => '·',
      null => null,
    };
  }

  static String? _areaTooltip(GitChangeArea? area) {
    return switch (area) {
      GitChangeArea.staged => 'Staged',
      GitChangeArea.unstaged => 'Unstaged',
      GitChangeArea.untracked => 'Untracked',
      null => null,
    };
  }
}
