import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_diff_viewer_screen.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_path_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const SourceControlPanel({
  super.key,
  required final String hostId,
  required final String workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      sourceControlControllerProvider(hostId, workspaceId),
    );
    return switch (state) {
      AsyncData(value: final snapshot) => _Body(
        hostId: hostId,
        workspaceId: workspaceId,
        snapshot: snapshot,
      ),
      AsyncError(:final error) => AleraEmptyState(
        icon: AleraIcons.gitCompare,
        message: error.toString(),
        action: FilledButton(
          onPressed: () => ref
              .read(
                sourceControlControllerProvider(hostId, workspaceId).notifier,
              )
              .reload(),
          child: const Text('Retry'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class const _Body({
  required final String hostId,
  required final String workspaceId,
  required final MobileGitStatusSnapshot snapshot,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!snapshot.isRepository) {
      return const AleraEmptyState(
        icon: AleraIcons.gitBranch,
        title: 'No repository',
        message: 'This workspace is not a Git repository.',
      );
    }
    final staged = snapshot.entries
        .where((entry) => entry.area == 'staged')
        .toList(growable: false);
    final unstaged = snapshot.entries
        .where((entry) => entry.area == 'unstaged')
        .toList(growable: false);
    final untracked = snapshot.entries
        .where((entry) => entry.area == 'untracked')
        .toList(growable: false);
    if (snapshot.entries.isEmpty) {
      return AleraEmptyState(
        icon: AleraIcons.check,
        title: 'Clean working tree',
        message: snapshot.branch == null
            ? 'There are no local changes.'
            : 'There are no local changes on ${snapshot.branch}.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: AleraTokens.space24),
      children: <Widget>[
        const Padding(
          padding: AleraTokens.contentPadding,
          child: AleraNotice(
            icon: AleraIcons.info,
            message: 'Read-only on mobile. Stage, unstage, and commit stay on desktop.',
          ),
        ),
        _Summary(snapshot: snapshot),
        ..._group(context, 'Staged', staged),
        ..._group(context, 'Unstaged', unstaged),
        ..._group(context, 'Untracked', untracked),
      ],
    );
  }

  List<Widget> _group(
    BuildContext context,
    String title,
    List<MobileGitChange> items,
  ) {
    if (items.isEmpty) {
      return const <Widget>[];
    }
    return <Widget>[
      AleraSectionHeader(
        label: title,
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space16,
          AleraTokens.space16,
          AleraTokens.space16,
          AleraTokens.space4,
        ),
        trailing: Text(
          '${items.length}',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AleraTokens.foregroundFaint),
        ),
      ),
      for (final change in items)
        _ChangeRow(
          change: change,
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => WorkspaceDiffViewerScreen(
                hostId: hostId,
                workspaceId: workspaceId,
                change: change,
              ),
            ),
          ),
        ),
    ];
  }
}

class const _Summary({required final MobileGitStatusSnapshot snapshot})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileCount = snapshot.changedFileCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space16,
        0,
        AleraTokens.space16,
        AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            AleraIcons.gitBranch,
            size: 16,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              snapshot.branch ?? 'Detached',
              maxLines: 1,
              overflow: .ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          Text(
            '$fileCount ${fileCount == 1 ? 'file' : 'files'}',
            style: theme.textTheme.bodySmall,
          ),
          if (snapshot.addedLineCount > 0) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            Text(
              '+${snapshot.addedLineCount}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.success,
              ),
            ),
          ],
          if (snapshot.removedLineCount > 0) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            Text(
              '-${snapshot.removedLineCount}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class const _ChangeRow({
  required final MobileGitChange change,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = workspaceFileBaseName(change.path);
    final parent = workspaceFileParentLabel(change.path);
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
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space16,
              vertical: AleraTokens.space8,
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
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
