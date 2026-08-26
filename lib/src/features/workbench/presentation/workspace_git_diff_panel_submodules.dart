part of 'workspace_git_diff_panel.dart';

class _SubmoduleChanges extends ConsumerWidget {
  const _SubmoduleChanges({
    required this.workspacePath,
    required this.entry,
    required this.depth,
    required this.busy,
    required this.onOpenGitDiff,
    this.onOpenFile,
    required this.onRevealInExplorer,
  });

  final String workspacePath;
  final GitChangeEntry entry;
  final int depth;
  final bool busy;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final ValueChanged<String>? onOpenFile;
  final ValueChanged<String> onRevealInExplorer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      workspaceSubmoduleStatusProvider(
        workspacePath: workspacePath,
        submodulePath: entry.path,
        area: entry.area,
      ),
    );
    return status.when(
      loading: () => _SubmoduleFeedbackRow(
        depth: depth,
        message: 'Loading submodule changes…',
      ),
      error: (error, _) => _SubmoduleFeedbackRow(
        depth: depth,
        message: 'Could not load submodule changes',
        tooltip: error.toString(),
      ),
      data: (result) {
        if (result.entries.isEmpty) {
          return _SubmoduleFeedbackRow(
            depth: depth,
            message: 'No changes in submodule',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final child in result.entries)
              _GitDiffFileRow(
                entry: child,
                absolutePath: _terminalPathForGitEntry(
                  workspacePath,
                  child.path,
                ),
                depth: depth,
                showRelativePath: true,
                busy: busy,
                onOpenFile: onOpenFile == null
                    ? null
                    : () => onOpenFile!(child.path),
                onRevealInExplorer: () => onRevealInExplorer(child.path),
                onStage: (_) {},
                onUnstage: (_) {},
                onDiscard: (_) {},
                onTap: () => unawaited(
                  onOpenGitDiff(
                    relativePath: child.path,
                    area: child.area,
                    scope: WorkspaceGitDiffScope.file,
                    preview: true,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SubmoduleFeedbackRow extends StatelessWidget {
  const _SubmoduleFeedbackRow({
    required this.depth,
    required this.message,
    this.tooltip,
  });

  final int depth;
  final String message;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      message,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: AleraTokens.foregroundFaint),
    );
    return Padding(
      padding: EdgeInsets.only(
        left: AleraTokens.space8 + (depth * AleraTokens.space12) + 16,
        right: AleraTokens.space8,
        top: AleraTokens.space4,
        bottom: AleraTokens.space4,
      ),
      child: tooltip == null ? text : Tooltip(message: tooltip!, child: text),
    );
  }
}
