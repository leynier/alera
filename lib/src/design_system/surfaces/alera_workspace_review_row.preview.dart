import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_review_row.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:flutter/material.dart';

void _action() {}
void _menu(Rect _) {}

@AleraPreview(name: 'Workspace Pull Request')
Widget workspaceReviewPreview() => const SizedBox(
  width: AleraTokens.workspaceDetailsWidth,
  child: AleraWorkspaceReviewRow(
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
  ),
);

@AleraPreview(name: 'Workspace Pull Request Failing Checks')
Widget workspaceReviewFailingPreview() => const SizedBox(
  width: AleraTokens.workspaceDetailsWidth,
  child: AleraWorkspaceReviewRow(
    label: '#124: Move the comparison snapshot into an isolate worker',
    stateLabel: 'Open',
    stateIcon: AleraIcons.gitPullRequest,
    stateColor: AleraTokens.success,
    tooltip: 'feature/isolate → main\nChecks failed',
    onOpen: _action,
    onMenu: _menu,
    checksLabel: '5 Checks',
    checksIcon: AleraIcons.cancel,
    checksColor: AleraTokens.error,
    onChecks: _action,
    actionLabel: 'Fix',
    actionCritical: true,
    onAction: _action,
  ),
);

@AleraPreview(name: 'Workspace Pull Request Merging')
Widget workspaceReviewMergingPreview() => const SizedBox(
  width: AleraTokens.workspaceDetailsWidth,
  child: AleraWorkspaceReviewRow(
    label: '#123: Add Workspace Details',
    stateLabel: 'Open',
    stateIcon: AleraIcons.gitPullRequest,
    stateColor: AleraTokens.success,
    tooltip: 'feature/details → main',
    onOpen: _action,
    onMenu: _menu,
    checksLabel: '2 Checks',
    checksIcon: AleraIcons.success,
    checksColor: AleraTokens.success,
    onChecks: _action,
    actionLabel: 'Merging…',
    actionPending: true,
  ),
);
