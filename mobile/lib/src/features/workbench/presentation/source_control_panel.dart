import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_diff_viewer_screen.dart';
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
    final staged = snapshot.entries.where((entry) => entry.area == 'staged');
    final unstaged = snapshot.entries.where(
      (entry) => entry.area == 'unstaged',
    );
    final untracked = snapshot.entries.where(
      (entry) => entry.area == 'untracked',
    );
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
      children: <Widget>[
        Padding(
          padding: AleraTokens.contentPadding,
          child: Text(
            'Source control is read-only on mobile. Stage, unstage, and commit stay on desktop.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (snapshot.branch != null)
          ListTile(
            leading: const Icon(AleraIcons.gitBranch),
            title: Text(snapshot.branch!),
            subtitle: const Text('Current branch'),
          ),
        ListTile(
          leading: const Icon(AleraIcons.gitCompare),
          title: Text(
            '${snapshot.changedFileCount} ${snapshot.changedFileCount == 1 ? 'file' : 'files'} · +${snapshot.addedLineCount} -${snapshot.removedLineCount}',
          ),
          subtitle: const Text('Diff summary'),
        ),
        ..._group(context, hostId, workspaceId, 'Staged', staged),
        ..._group(context, hostId, workspaceId, 'Unstaged', unstaged),
        ..._group(context, hostId, workspaceId, 'Untracked', untracked),
      ],
    );
  }

  List<Widget> _group(
    BuildContext context,
    String hostId,
    String workspaceId,
    String title,
    Iterable<MobileGitChange> entries,
  ) {
    final items = entries.toList(growable: false);
    if (items.isEmpty) {
      return const <Widget>[];
    }
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space16,
          AleraTokens.space12,
          AleraTokens.space16,
          AleraTokens.space4,
        ),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final change in items)
        ListTile(
          minTileHeight: AleraTokens.minTapTarget,
          title: Text(change.path),
          subtitle: Text(_subtitle(change)),
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

  String _subtitle(MobileGitChange change) {
    final counts = <String>[
      change.status,
      if (change.added != null) '+${change.added}',
      if (change.removed != null) '-${change.removed}',
    ];
    return counts.join(' · ');
  }
}
