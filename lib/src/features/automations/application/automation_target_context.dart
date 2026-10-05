import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_draft.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';

/// Selects [type] and fills only the fields the entry context determines
/// without ambiguity. Choosing the type stays the user's act; the context may
/// never choose it, and an ambiguous field stays empty.
AutomationDraft chooseAutomationTargetType(
  AutomationDraft draft,
  AutomationTargetType type,
  AutomationWorkbenchContext context,
  AutomationAuthoringRequest? request,
) {
  var next = draft.withTargetType(type);
  final filled = <AutomationDraftField, String>{};
  final origin = context.workspace(
    request?.originWorkspaceId ?? draft.originWorkspaceId,
  );
  final projectId = origin?.projectId ?? request?.projectId;
  final project = context.project(projectId);

  String? single(Iterable<String> values) {
    final unique = values.toSet();
    return unique.length == 1 ? unique.single : null;
  }

  final workspace =
      origin ??
      (projectId == null
          ? null
          : switch (context.workspacesOf(projectId)) {
              [final only] => only,
              _ => null,
            });
  switch (type) {
    case AutomationTargetType.freshTab:
      if (workspace != null) filled[.workspaceId] = workspace.id;
    case AutomationTargetType.managedWorkspace:
      final source = workspace;
      final sourceProject = context.project(source?.projectId);
      if (source != null && sourceProject?.isGitRepository == true) {
        filled[.workspaceId] = source.id;
        final branch = source.branch?.trim();
        if (branch != null && branch.isNotEmpty) filled[.sourceBranch] = branch;
      }
    case AutomationTargetType.projectWorktree:
      if (project?.isGitRepository == true) filled[.projectId] = project!.id;
    case AutomationTargetType.projectCheckout:
      if (project != null) filled[.projectId] = project.id;
    case AutomationTargetType.existingTab:
      if (workspace != null) {
        filled[.workspaceId] = workspace.id;
        final tabs = context.conversationTabs(workspace.id);
        if (tabs case [final tab]) {
          filled[.tabId] = tab.id;
          final conversation = automationConversationId(tab);
          if (conversation != null) filled[.conversationId] = conversation;
        }
      }
  }
  if (type != AutomationTargetType.existingTab) {
    final profile = single(context.profiles.map((profile) => profile.id));
    if (profile != null) filled[.agentProfileId] = profile;
  }
  next = next.copyWith(targetFields: filled, fromContext: filled.keys.toSet());
  return next;
}
