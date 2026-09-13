import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/linked_issues/application/linked_issue_providers.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue.dart';
import 'package:alera/src/features/linked_issues/presentation/link_issue_dialog.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/uri/uri_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String openLinkedIssueMenuAction = 'open-linked-issue';
const String changeLinkedIssueMenuAction = 'change-linked-issue';
const String unlinkIssueMenuAction = 'unlink-issue';
const String linkIssueMenuAction = 'link-issue';

const Set<String> _linkedIssueMenuActions = <String>{
  openLinkedIssueMenuAction,
  changeLinkedIssueMenuAction,
  unlinkIssueMenuAction,
  linkIssueMenuAction,
};

bool isLinkedIssueMenuAction(String? action) =>
    _linkedIssueMenuActions.contains(action);

/// Context-menu entries for a workspace's issue: nothing when the host cannot
/// store links, `Link Issue` without one, and open, change and unlink with one.
List<PopupMenuEntry<String>> linkedIssueMenuEntries({
  required bool supported,
  required LinkedIssue? linkedIssue,
}) {
  if (!supported) {
    return const <PopupMenuEntry<String>>[];
  }
  if (linkedIssue == null) {
    return const <PopupMenuEntry<String>>[
      AleraDropdownEntry<String>(
        value: linkIssueMenuAction,
        leading: Icon(AleraIcons.issueUnknown, size: 16),
        label: 'Link Issue',
      ),
    ];
  }
  return const <PopupMenuEntry<String>>[
    AleraDropdownEntry<String>(
      value: openLinkedIssueMenuAction,
      leading: Icon(AleraIcons.external, size: 16),
      label: 'Open Issue in Browser',
    ),
    AleraDropdownEntry<String>(
      value: changeLinkedIssueMenuAction,
      leading: Icon(AleraIcons.link, size: 16),
      label: 'Change Linked Issue',
    ),
    AleraDropdownEntry<String>(
      value: unlinkIssueMenuAction,
      leading: Icon(AleraIcons.unlink, size: 16),
      label: 'Unlink Issue',
    ),
  ];
}

/// Runs one of the actions from [linkedIssueMenuEntries] for [workspace].
Future<void> runLinkedIssueMenuAction(
  BuildContext context,
  ProviderContainer container, {
  required Workspace workspace,
  required String action,
}) async {
  final repository = container.read(linkedIssueRepositoryProvider);
  final linkedIssue = container.read(
    workspaceLinkedIssueProvider(workspace.id),
  );
  switch (action) {
    case openLinkedIssueMenuAction:
      final url = linkedIssue?.url;
      if (url == null) {
        return;
      }
      final uri = Uri.tryParse(url);
      if (uri == null) {
        AleraToast.show(
          context,
          message: 'The linked issue URL is not valid',
          tone: .error,
        );
        return;
      }
      await container.read(externalUriLauncherProvider).open(uri);
    case linkIssueMenuAction || changeLinkedIssueMenuAction:
      await showLinkIssueDialog(
        context,
        repository: repository,
        workspaceId: workspace.id,
        workspaceName: workspace.name,
        initialUrl: action == changeLinkedIssueMenuAction
            ? linkedIssue?.url
            : null,
      );
    case unlinkIssueMenuAction:
      if (linkedIssue == null) {
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AleraConfirmDialog(
          title: 'Unlink Issue ${linkedIssue.reference}?',
          message:
              'This removes the issue link from ${workspace.name}. The issue itself will not be changed.',
          confirmLabel: 'Unlink Issue',
        ),
      );
      if (confirmed != true) {
        return;
      }
      try {
        await repository.unlink(workspace.id);
      } catch (error) {
        AleraToast.publish(
          message:
              'Could not unlink the issue: ${userFacingExceptionMessage(error)}',
          tone: .error,
        );
      }
  }
}

/// Starts [runLinkedIssueMenuAction] without awaiting it from a menu handler.
void launchLinkedIssueMenuAction(
  BuildContext context, {
  required Workspace workspace,
  required String action,
}) {
  unawaited(
    runLinkedIssueMenuAction(
      context,
      ProviderScope.containerOf(context, listen: false),
      workspace: workspace,
      action: action,
    ),
  );
}
