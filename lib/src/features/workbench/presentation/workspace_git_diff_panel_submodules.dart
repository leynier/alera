part of 'workspace_git_diff_panel.dart';

class const _SubmoduleChanges({
  required final String workspacePath,
  required final GitChangeEntry entry,
  required final int depth,
  required final bool busy,
  required final OpenGitDiffTabCallback onOpenGitDiff,
  final ValueChanged<String>? onOpenFile,
  required final ValueChanged<String> onRevealInExplorer,
}) extends ConsumerWidget {
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
          crossAxisAlignment: .stretch,
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
                    scope: .file,
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

class const _SubmoduleFeedbackRow({
  required final int depth,
  required final String message,
  final String? tooltip,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final text = Text(
      message,
      maxLines: 1,
      overflow: .ellipsis,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AleraTokens.foregroundFaint),
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
