import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_actions_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_commit_draft.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_amend_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every source control action the phone offers, labelled like the desktop
/// Source Control menu.
enum SourceControlCommand {
  commit('Commit', AleraIcons.gitCommit),
  commitPush('Commit & Push', AleraIcons.gitPush),
  commitSync('Commit & Sync', AleraIcons.gitSync),
  amend('Commit Amend', AleraIcons.gitAmend),
  refresh('Refresh', AleraIcons.refresh),
  stageAll('Stage All', AleraIcons.gitStage),
  unstageAll('Unstage All', AleraIcons.gitUnstage),
  discardAll('Discard All', AleraIcons.gitDiscard),
  fetch('Fetch', AleraIcons.gitFetch),
  pull('Pull', AleraIcons.gitPull),
  push('Push', AleraIcons.gitPush),
  sync('Sync', AleraIcons.gitSync),
  publishBranch('Publish Branch', AleraIcons.gitPublish),
  stash('Stash', AleraIcons.gitStash),
  stashPop('Stash Pop', AleraIcons.gitStashPop);

  SourceControlCommand(this.label, this.icon);

  final String label;
  final IconData icon;

  static const List<SourceControlCommand> commitOptions =
      <SourceControlCommand>[commit, commitPush, commitSync, amend];

  static const List<SourceControlCommand> menu = <SourceControlCommand>[
    refresh,
    stageAll,
    unstageAll,
    discardAll,
    fetch,
    pull,
    push,
    sync,
    publishBranch,
    stash,
    stashPop,
  ];

  /// Whether the runtime allows this command. Commit variants that type a
  /// message also need one, which only the phone knows.
  bool isAvailable(MobileGitStatusSnapshot snapshot, {String message = ''}) {
    final actions = snapshot.actions;
    final hasMessage = message.trim().isNotEmpty;
    return switch (this) {
      commit => actions.commit && hasMessage,
      commitPush => actions.commitPush && hasMessage,
      commitSync => actions.commitSync && hasMessage,
      amend => actions.amend,
      refresh => true,
      stageAll => actions.stageAll,
      unstageAll => actions.unstageAll,
      discardAll => actions.discardAll,
      fetch => actions.fetch,
      pull => actions.pull,
      push => actions.push,
      sync => actions.sync,
      publishBranch => actions.publishBranch,
      stash => actions.stash,
      stashPop => actions.stashPop,
    };
  }

  /// The one-tap action, with Commit first as on desktop: it wins as soon as
  /// there is something staged and a message to commit it with.
  static SourceControlCommand primary(
    MobileGitStatusSnapshot snapshot,
    String message,
  ) {
    if (commit.isAvailable(snapshot, message: message)) {
      return commit;
    }
    return switch (snapshot.primaryAction) {
      'publishBranch' => publishBranch,
      'sync' => sync,
      'pull' => pull,
      'push' => push,
      'stageAll' => stageAll,
      _ => fetch,
    };
  }
}

/// Runs source control work for one workspace from a widget, reporting the
/// outcome in a snack bar.
class const SourceControlCommandRunner({
  required final BuildContext context,
  required final WidgetRef ref,
  required final String hostId,
  required final String workspaceId,
}) {
  Future<void> perform(
    SourceControlCommand command,
    MobileGitStatusSnapshot snapshot,
  ) async {
    final draft = ref.read(
      sourceControlCommitDraftProvider(hostId, workspaceId),
    );
    switch (command) {
      case .refresh:
        await ref
            .read(sourceControlControllerProvider(hostId, workspaceId).notifier)
            .reload();
      case .commit || .commitPush || .commitSync:
        if (draft.trim().isEmpty) {
          _show('Enter a commit message.');
          return;
        }
        // The draft is cleared by the controller once the commit lands, so a
        // commit that finishes after this sheet closed still clears it.
        await write(
          MobileGitWrite.commit(
            draft,
            then: switch (command) {
              .commitPush => MobileCommitFollowUp.push,
              .commitSync => MobileCommitFollowUp.sync,
              _ => null,
            },
          ),
          successMessage: switch (command) {
            .commitPush => 'Committed and pushed',
            .commitSync => 'Committed and synced',
            _ => 'Committed',
          },
        );
      case .amend:
        await _amend(snapshot.repository.headMessage);
      case .stageAll:
        await write(MobileGitWrite.stage(), successMessage: 'Staged');
      case .unstageAll:
        await write(MobileGitWrite.unstage(), successMessage: 'Unstaged');
      case .discardAll:
        await discard();
      case .fetch:
        await write(MobileGitWrite.fetch(), successMessage: 'Fetched');
      case .pull:
        await write(MobileGitWrite.pull(), successMessage: 'Pulled');
      case .push:
        await write(MobileGitWrite.push(), successMessage: 'Pushed');
      case .sync:
        await write(MobileGitWrite.sync(), successMessage: 'Synced');
      case .publishBranch:
        await write(MobileGitWrite.push(), successMessage: 'Branch published');
      case .stash:
        await write(MobileGitWrite.stash(), successMessage: 'Stashed');
      case .stashPop:
        await _stashPop(snapshot.stashes);
    }
  }

  Future<bool> write(
    MobileGitWrite write, {
    required String successMessage,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final error = await ref
        .read(
          sourceControlActionsControllerProvider(hostId, workspaceId).notifier,
        )
        .run(write);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error ?? successMessage)));
    return error == null;
  }

  /// Discards after a destructive confirmation: untracked files are deleted
  /// from disk, not moved anywhere they could be recovered from.
  Future<bool> discard({String? path, String? area}) async {
    final target = path ?? area;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: target == null ? 'Discard All Changes?' : 'Discard Changes?',
        message: switch ((path, area)) {
          (final path?, _) =>
            'This permanently discards unstaged and untracked changes in "$path".',
          (null, final area?) =>
            'This permanently discards changes in "$area".',
          _ => 'This permanently discards unstaged and untracked changes in this workspace.',
        },
        confirmLabel: 'Discard',
        destructive: true,
      ),
    );
    if (confirmed != true || !context.mounted) {
      return false;
    }
    return write(
      MobileGitWrite.discard(path: path, area: area),
      successMessage: path == null ? 'Changes discarded' : 'Change discarded',
    );
  }

  Future<void> _amend(String? headMessage) async {
    if (headMessage == null || headMessage.trim().isEmpty) {
      return;
    }
    final message = await showDialog<String>(
      context: context,
      builder: (_) => SourceControlAmendDialog(initialMessage: headMessage),
    );
    if (message == null || !context.mounted) {
      return;
    }
    await write(
      MobileGitWrite.commit(message, amend: true),
      successMessage: 'Commit amended',
    );
  }

  Future<void> _stashPop(List<MobileGitStash> stashes) async {
    if (stashes.isEmpty) {
      return;
    }
    final index = stashes.length == 1
        ? stashes.single.index
        : await showAleraActionSheet<int>(
            context,
            entries: <AleraActionSheetEntry<int>>[
              for (final stash in stashes)
                AleraActionSheetEntry<int>(
                  value: stash.index,
                  label: stash.message.isEmpty
                      ? 'stash@{${stash.index}}'
                      : 'stash@{${stash.index}}: ${stash.message}',
                  leading: const Icon(AleraIcons.gitStashPop),
                ),
            ],
          );
    if (index == null || !context.mounted) {
      return;
    }
    await write(MobileGitWrite.stashPop(index), successMessage: 'Stash popped');
  }

  void _show(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Offers [commands] that the runtime currently allows and runs the chosen one.
Future<void> showSourceControlCommandSheet(
  SourceControlCommandRunner runner,
  MobileGitStatusSnapshot snapshot,
  List<SourceControlCommand> commands, {
  String message = '',
}) async {
  final available = commands
      .where((command) => command.isAvailable(snapshot, message: message))
      .toList(growable: false);
  if (available.isEmpty) {
    return;
  }
  final chosen = await showAleraActionSheet<SourceControlCommand>(
    runner.context,
    entries: <AleraActionSheetEntry<SourceControlCommand>>[
      for (final command in available)
        AleraActionSheetEntry<SourceControlCommand>(
          value: command,
          label: command.label,
          leading: Icon(command.icon),
        ),
    ],
  );
  if (chosen != null && runner.context.mounted) {
    await runner.perform(chosen, snapshot);
  }
}
