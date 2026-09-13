import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_actions_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_branch_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_change_row.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_commands.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_commit_composer.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_header.dart';
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
    final writing =
        ref.watch(
          sourceControlActionsControllerProvider(hostId, workspaceId),
        ) !=
        null;
    final controller = ref.read(
      sourceControlControllerProvider(hostId, workspaceId).notifier,
    );
    if (state.value case final snapshot?) {
      return Column(
        children: <Widget>[
          if (state.isLoading || writing)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.reload,
              child: _Body(
                hostId: hostId,
                workspaceId: workspaceId,
                snapshot: snapshot,
                busy: writing,
                refreshError: state.hasError && !state.isLoading
                    ? state.error
                    : null,
              ),
            ),
          ),
        ],
      );
    }
    if (state case AsyncError(:final error) when !state.isLoading) {
      return AleraEmptyState(
        icon: AleraIcons.gitCompare,
        message: sourceControlErrorMessage(error),
        action: FilledButton(
          onPressed: controller.reload,
          child: const Text('Retry'),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

class const _Body({
  required final String hostId,
  required final String workspaceId,
  required final MobileGitStatusSnapshot snapshot,
  required final bool busy,
  final Object? refreshError,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshNotice = switch (refreshError) {
      final error? => Padding(
        padding: AleraTokens.contentPadding,
        child: AleraNotice(
          icon: AleraIcons.cloudOff,
          message:
              'Could not refresh source control: ${sourceControlErrorMessage(error)}',
        ),
      ),
      null => null,
    };
    if (!snapshot.isRepository) {
      return _ScrollableState(
        notice: refreshNotice,
        child: const AleraEmptyState(
          icon: AleraIcons.gitBranch,
          title: 'No repository',
          message: 'This workspace is not a Git repository.',
        ),
      );
    }
    final writable = snapshot.writable;
    final cleanMessage = snapshot.branch == null
        ? 'There are no local changes.'
        : 'There are no local changes on ${snapshot.branch}.';
    if (snapshot.entries.isEmpty && !writable) {
      return _ScrollableState(
        notice: refreshNotice,
        child: AleraEmptyState(
          icon: AleraIcons.check,
          title: 'Clean working tree',
          message: cleanMessage,
        ),
      );
    }
    final runner = SourceControlCommandRunner(
      context: context,
      ref: ref,
      hostId: hostId,
      workspaceId: workspaceId,
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AleraTokens.space24),
      children: <Widget>[
        ?refreshNotice,
        if (!writable)
          const Padding(
            padding: AleraTokens.contentPadding,
            child: AleraNotice(
              icon: AleraIcons.info,
              message: 'Update the paired Alera runtime to stage and commit from mobile.',
            ),
          ),
        if (writable) const SizedBox(height: AleraTokens.space8),
        SourceControlHeader(
          snapshot: snapshot,
          onBranchTap: writable && !busy
              ? () => showSourceControlBranchSheet(runner, snapshot.branch)
              : null,
          onMoreActions: writable && !busy
              ? () => showSourceControlCommandSheet(
                  runner,
                  snapshot,
                  SourceControlCommand.menu,
                )
              : null,
        ),
        if (writable)
          SourceControlCommitComposer(
            hostId: hostId,
            workspaceId: workspaceId,
            snapshot: snapshot,
            busy: busy,
          ),
        if (snapshot.entries.isEmpty)
          AleraEmptyState(
            icon: AleraIcons.check,
            title: 'Clean working tree',
            message: cleanMessage,
          ),
        for (final (title, area) in const <(String, String)>[
          ('Staged', 'staged'),
          ('Unstaged', 'unstaged'),
          ('Untracked', 'untracked'),
        ])
          ..._group(context, runner, title, area),
      ],
    );
  }

  List<Widget> _group(
    BuildContext context,
    SourceControlCommandRunner runner,
    String title,
    String area,
  ) {
    final items = snapshot.entries
        .where((entry) => entry.area == area)
        .toList(growable: false);
    if (items.isEmpty) {
      return const <Widget>[];
    }
    final writable = snapshot.writable;
    final canStage = items.any((entry) => entry.canStage);
    final canUnstage = items.any((entry) => entry.canUnstage);
    final canDiscard = items.any((entry) => entry.canDiscard);
    return <Widget>[
      AleraSectionHeader(
        label: title,
        padding: EdgeInsets.fromLTRB(
          AleraTokens.space16,
          AleraTokens.space16,
          writable ? AleraTokens.space4 : AleraTokens.space16,
          AleraTokens.space4,
        ),
        trailing: Row(
          mainAxisSize: .min,
          children: <Widget>[
            Text(
              '${items.length}',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: AleraTokens.foregroundFaint),
            ),
            if (writable && (canStage || canUnstage || canDiscard))
              AleraIconButton(
                tooltip: '$title Actions',
                icon: AleraIcons.more,
                onPressed: busy
                    ? null
                    : () => _showGroupActions(
                        runner,
                        area: area,
                        canStage: canStage,
                        canUnstage: canUnstage,
                        canDiscard: canDiscard,
                      ),
              ),
          ],
        ),
      ),
      for (final change in items)
        SourceControlChangeRow(
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
          onLongPress: writable && !busy
              ? () => showSourceControlChangeActions(runner, change)
              : null,
          showStageToggle: writable,
          onToggleStaged: writable && !busy
              ? () => toggleSourceControlChange(runner, change)
              : null,
        ),
    ];
  }

  Future<void> _showGroupActions(
    SourceControlCommandRunner runner, {
    required String area,
    required bool canStage,
    required bool canUnstage,
    required bool canDiscard,
  }) async {
    final chosen = await showAleraActionSheet<MobileGitWriteAction>(
      runner.context,
      entries: <AleraActionSheetEntry<MobileGitWriteAction>>[
        if (canStage)
          const AleraActionSheetEntry(
            value: .stage,
            label: 'Stage All',
            leading: Icon(AleraIcons.gitStage),
          ),
        if (canUnstage)
          const AleraActionSheetEntry(
            value: .unstage,
            label: 'Unstage All',
            leading: Icon(AleraIcons.gitUnstage),
          ),
        if (canDiscard)
          const AleraActionSheetEntry(
            value: .discard,
            label: 'Discard All',
            leading: Icon(AleraIcons.gitDiscard),
          ),
      ],
    );
    if (!runner.context.mounted) {
      return;
    }
    switch (chosen) {
      case .stage:
        await runner.write(
          MobileGitWrite.stage(area: area),
          successMessage: 'Staged',
        );
      case .unstage:
        await runner.write(
          MobileGitWrite.unstage(area: area),
          successMessage: 'Unstaged',
        );
      case .discard:
        await runner.discard(area: area);
      case _:
        return;
    }
  }
}

/// Stages an unstaged or untracked file, or unstages a staged one.
Future<bool> toggleSourceControlChange(
  SourceControlCommandRunner runner,
  MobileGitChange change,
) {
  return change.canUnstage
      ? runner.write(
          MobileGitWrite.unstage(path: change.path, area: change.area),
          successMessage: 'Unstaged',
        )
      : runner.write(
          MobileGitWrite.stage(path: change.path, area: change.area),
          successMessage: 'Staged',
        );
}

/// The per-file actions behind a long press. Resolves true when a write
/// succeeded, so a diff screen knows its content went stale.
Future<bool> showSourceControlChangeActions(
  SourceControlCommandRunner runner,
  MobileGitChange change,
) async {
  final chosen = await showAleraActionSheet<MobileGitWriteAction>(
    runner.context,
    entries: <AleraActionSheetEntry<MobileGitWriteAction>>[
      if (change.canStage)
        const AleraActionSheetEntry(
          value: .stage,
          label: 'Stage',
          leading: Icon(AleraIcons.gitStage),
        ),
      if (change.canUnstage)
        const AleraActionSheetEntry(
          value: .unstage,
          label: 'Unstage',
          leading: Icon(AleraIcons.gitUnstage),
        ),
      if (change.canDiscard)
        const AleraActionSheetEntry(
          value: .discard,
          label: 'Discard',
          leading: Icon(AleraIcons.gitDiscard),
        ),
    ],
  );
  if (!runner.context.mounted) {
    return false;
  }
  return switch (chosen) {
    .stage || .unstage => toggleSourceControlChange(runner, change),
    .discard => runner.discard(path: change.path, area: change.area),
    _ => Future<bool>.value(false),
  };
}

/// Keeps pull-to-refresh working on the empty states, which do not scroll.
class const _ScrollableState({
  required final Widget child,
  final Widget? notice,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            children: <Widget>[
              ?notice,
              SizedBox(height: constraints.maxHeight, child: child),
            ],
          ),
        ),
      ),
    );
  }
}
