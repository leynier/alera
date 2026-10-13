import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_details_card.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_review_row.dart';
import 'package:alera/src/design_system/surfaces/workspace_details_density.dart';
import 'package:flutter/material.dart';

void _action() {}
void _menu(Rect _) {}

final _changes = Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(
      '+42',
      style: AleraTokens.monoCompactStyle.copyWith(color: AleraTokens.success),
    ),
    const SizedBox(width: AleraTokens.space6),
    Text(
      '-8',
      style: AleraTokens.monoCompactStyle.copyWith(color: AleraTokens.error),
    ),
  ],
);

Widget _card({
  WorkspaceDetailsDensity density = .full,
  bool running = false,
  String? error,
}) => SizedBox(
  width: AleraTokens.workspaceDetailsWidth,
  child: AleraWorkspaceDetailsCard(
    density: density,
    onOptions: _menu,
    afterBranch: AleraWorkspaceReviewRow(
      label: '#123: Add Workspace Details',
      stateLabel: 'Open',
      stateIcon: AleraIcons.gitPullRequest,
      stateColor: AleraTokens.success,
      tooltip: 'feature/details → main\n2 checks passed',
      onOpen: _action,
      onMenu: _menu,
      checksLabel: '2 Checks',
      checksIcon: AleraIcons.success,
      checksColor: AleraTokens.success,
      onChecks: _action,
      actionLabel: 'Merge',
      onAction: _action,
      compact: density != .full,
    ),
    rows: [
      const AleraWorkspaceDetailRow(
        label: 'This Device',
        leading: Icon(AleraIcons.workspaceMain),
        onPressed: _action,
        onMenu: _menu,
      ),
      const AleraWorkspaceDetailRow(
        label: 'Open In File Manager',
        leading: Icon(AleraIcons.folder),
        onPressed: _action,
        onMenu: _menu,
      ),
      const AleraWorkspaceDetailRow(
        label: 'feature/workspace-details',
        subtitle: 'Compare against origin/main',
        leading: Icon(AleraIcons.gitBranch),
        onPressed: _action,
        onMenu: _menu,
      ),
      AleraWorkspaceDetailRow(
        label: running ? 'Pushing' : 'Commit, Push & Create PR',
        subtitle: error ?? (running ? '12s · Writing objects: 64%' : null),
        subtitleColor: error == null ? null : AleraTokens.error,
        leading: running
            ? const AleraWorkspaceDetailSpinner()
            : error != null
            ? const Icon(AleraIcons.error, color: AleraTokens.error)
            : const Icon(AleraIcons.gitPush),
        hasMenu: true,
        onPressed: running ? null : _action,
        onMenu: running ? null : _menu,
      ),
      AleraWorkspaceDetailRow(
        label: 'Changes',
        leading: const Icon(AleraIcons.diff),
        trailing: _changes,
        onPressed: _action,
      ),
    ],
  ),
);

@AleraPreview(name: 'Workspace Details')
Widget workspaceDetailsPreview() => _card();

@AleraPreview(name: 'Workspace Details Progress')
Widget workspaceDetailsProgressPreview() => _card(running: true);

@AleraPreview(name: 'Workspace Details Error')
Widget workspaceDetailsErrorPreview() =>
    _card(error: 'Push rejected: the remote branch moved.');

@AleraPreview(name: 'Workspace Details Essential')
Widget workspaceDetailsEssentialPreview() => _card(density: .essential);
