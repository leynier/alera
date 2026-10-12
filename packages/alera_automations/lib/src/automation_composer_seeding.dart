import 'package:alera_automations/src/automation_draft.dart';
import 'package:alera_automations/src/automation_models.dart';
import 'package:alera_automations/src/automation_target_choice.dart';

/// Where a composer was opened from, already resolved by the app against
/// its own workbench state.
///
/// [workspaceId] is the origin workspace when it still exists, and
/// [worktreeProjectId] the project of the context when it is a Git project
/// a worktree can be created from. [originWorkspaceId] is kept on the draft
/// as given.
class const AutomationComposerOrigin({
  final String? originWorkspaceId,
  final String? workspaceId,
  final String? worktreeProjectId,
  final String? sectionId,
  final String? profileId,
});

/// The starting draft of a new automation, seeded from where it was started:
///
/// - a workspace: a new agent tab in that workspace, filed in its section;
/// - a Git project: a new worktree of it (the source branch is filled once
///   the branches load, see [automationSeedSourceBranch]); any other project
///   seeds nothing until its folders load (see [automationSeedProjectFolder]);
/// - a section: only the section new workspaces land in;
/// - anywhere else: no destination, so the user has to choose one.
///
/// Seeded destination fields are marked From Context.
AutomationDraft seedAutomationDraft(AutomationComposerOrigin origin) {
  var draft = AutomationDraft(originWorkspaceId: origin.originWorkspaceId);
  final seeded = <AutomationDraftField, String>{};
  if (origin.workspaceId case final workspaceId?) {
    draft = draft.withTargetType(AutomationTargetType.freshTab);
    seeded[.workspaceId] = workspaceId;
  } else if (origin.worktreeProjectId case final projectId?) {
    draft = draft.withTargetType(AutomationTargetType.worktree);
    seeded[.projectId] = projectId;
  }
  return draft.copyWith(
    targetFields: <AutomationDraftField, String>{
      ...seeded,
      .agentProfileId: ?origin.profileId,
      .workspaceSectionId: ?origin.sectionId,
    },
    fromContext: seeded.keys.toSet(),
  );
}

/// The profile a new automation starts with: the one used last in this
/// session, else the default from settings, else the only profile there is.
String? automationPreferredProfileId(
  Iterable<String> profileIds, {
  String? lastUsed,
  String? settingsDefault,
}) {
  final known = profileIds.toSet();
  if (lastUsed != null && known.contains(lastUsed)) return lastUsed;
  if (settingsDefault != null && known.contains(settingsDefault)) {
    return settingsDefault;
  }
  return known.length == 1 ? known.single : null;
}

/// Picks the project's only folder when nothing else was seeded.
AutomationDraft automationSeedProjectFolder(
  AutomationDraft draft,
  String projectId,
  List<({String hostId, String path})> folders,
) {
  if (draft.targetType != null || folders.length != 1) return draft;
  final next = applyAutomationDestination(
    draft,
    AutomationTargetChoice.projectCheckout,
    <AutomationDraftField, String>{
      .projectId: projectId,
      .hostId: folders.single.hostId,
    },
  );
  return next.copyWith(
    fromContext: const <AutomationDraftField>{.projectId, .hostId},
  );
}

/// Fills the source branch of a project worktree with the branch New
/// Workspace would preselect, unless the user already chose one. It is From
/// Context exactly when the project was.
AutomationDraft automationSeedSourceBranch(
  AutomationDraft draft,
  String projectId,
  String? branch,
) {
  if (branch == null ||
      branch.isEmpty ||
      AutomationTargetChoice.of(draft) !=
          AutomationTargetChoice.projectWorktree ||
      draft.field(.projectId) != projectId ||
      (draft.field(.sourceBranch) ?? '').isNotEmpty) {
    return draft;
  }
  final fromContext = draft.fromContext.contains(
    AutomationDraftField.projectId,
  );
  final next = draft.withTargetField(.sourceBranch, branch);
  return fromContext
      ? next.copyWith(
          fromContext: <AutomationDraftField>{
            ...next.fromContext,
            .sourceBranch,
          },
        )
      : next;
}

/// Selects [choice] with [fields], keeping the agent profile and the section
/// the user already picked: changing where a run goes should not reset who
/// runs it.
AutomationDraft applyAutomationDestination(
  AutomationDraft draft,
  AutomationTargetChoice choice,
  Map<AutomationDraftField, String> fields,
) {
  final profile = draft.field(.agentProfileId);
  final section = draft.workspaceSectionId;
  final next = choice.applyTo(draft);
  return next.copyWith(
    targetFields: <AutomationDraftField, String>{
      ...next.targetFields,
      ...fields,
      // A conversation target ignores the profile; keeping it means
      // switching back does not ask for it again.
      .agentProfileId: ?profile,
      .workspaceSectionId: ?section,
    },
  );
}
