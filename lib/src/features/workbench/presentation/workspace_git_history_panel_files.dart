part of 'workspace_git_diff_panel.dart';

class _CommitFilesState {
  const new loading()
    : entries = const <GitCommitChangeEntry>[],
      error = null,
      loading = true;

  const new ready({required this.entries}) : error = null, loading = false;

  const new error({required this.error})
    : entries = const <GitCommitChangeEntry>[],
      loading = false;

  final List<GitCommitChangeEntry> entries;
  final String? error;
  final bool loading;
}

class const _CommitFiles({
  required final _CommitFilesState state,
  required final String? author,
  required final DateTime? timestamp,
  required final VoidCallback onOpenAll,
  required final ValueChanged<GitCommitChangeEntry> onOpenFile,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (author != null && author!.trim().isNotEmpty) author!,
      if (timestamp != null) _formatTimestamp(timestamp!),
    ].join(' · ');
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.surface),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: 40,
                right: AleraTokens.space8,
                top: AleraTokens.space4,
                bottom: AleraTokens.space2,
              ),
              child: Text(
                meta,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AleraTokens.foregroundFaint),
              ),
            ),
          if (state.loading)
            const Padding(
              padding: EdgeInsets.fromLTRB(40, 4, 8, 6),
              child: Text('Loading files...'),
            )
          else if (state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 4, 8, 6),
              child: Text(
                state.error!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.error),
              ),
            )
          else if (state.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(40, 4, 8, 6),
              child: Text('No file changes'),
            )
          else ...<Widget>[
            for (final entry in state.entries)
              _CommitFileRow(entry: entry, onOpen: () => onOpenFile(entry)),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InkWell(
                onTap: onOpenAll,
                mouseCursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 5, 8, 7),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        AleraIcons.external,
                        size: 13,
                        color: AleraTokens.foregroundMuted,
                      ),
                      const SizedBox(width: AleraTokens.space6),
                      Text(
                        'Open All Changes',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: AleraTokens.foregroundMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class const _CommitFileRow({
  required final GitCommitChangeEntry entry,
  required final VoidCallback onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final label = entry.oldPath == null
        ? entry.path
        : '${entry.oldPath} -> ${entry.path}';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onOpen,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 4, 8, 4),
          child: Row(
            children: <Widget>[
              AleraFileIcon(pathOrName: entry.path, kind: .file, size: 14),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: AleraTokens.monoStyle.copyWith(
                    color: AleraTokens.foregroundMuted,
                    fontSize: 11,
                  ),
                ),
              ),
              _CommitStats(entry: entry),
              const SizedBox(width: AleraTokens.space6),
              _GitStatusLabel(status: entry.status),
            ],
          ),
        ),
      ),
    );
  }
}

class const _CommitStats({required final GitCommitChangeEntry entry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        if (entry.added case final added? when added > 0)
          Text('+$added', style: style?.copyWith(color: AleraTokens.success)),
        if (entry.removed case final removed? when removed > 0) ...<Widget>[
          const SizedBox(width: AleraTokens.space4),
          Text('-$removed', style: style?.copyWith(color: AleraTokens.error)),
        ],
      ],
    );
  }
}

class const _HistoryLoadingMessage() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class const _HistoryMessage({required final String message})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}
