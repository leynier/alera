import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'automation_composer_defaults.g.dart';

/// The agent profile the last saved automation used in this session, so the
/// next one starts with it.
@Riverpod(keepAlive: true)
class AutomationLastAgentProfile extends _$AutomationLastAgentProfile {
  @override
  String? build() => null;

  void remember(String? id) {
    if (id != null && id.isNotEmpty) state = id;
  }
}

/// The profile a new automation starts with: the one used last in this
/// session, else the default from Settings, else the only profile there is.
String? automationPreferredProfileId(
  List<AgentProfile> profiles, {
  String? lastUsed,
  String? settingsDefault,
}) {
  bool known(String? id) =>
      id != null && profiles.any((profile) => profile.id == id);
  if (known(lastUsed)) return lastUsed;
  if (known(settingsDefault)) return settingsDefault;
  return profiles.length == 1 ? profiles.single.id : null;
}

/// The starting draft of a new automation, seeded from where it was started:
///
/// - a workspace: a new agent tab in that workspace, filed in its section;
/// - a project: a new worktree of it when it is a Git project on this
///   computer (the source branch is filled once the branches load, see
///   [automationSeedSourceBranch]), otherwise nothing until its folders load
///   (see [automationSeedProjectFolder]);
/// - a section: only the section new workspaces land in;
/// - anywhere else: no destination, so the user has to choose one.
///
/// Seeded destination fields are marked From Context.
AutomationDraft seedAutomationComposerDraft(
  AutomationAuthoringRequest request,
  AutomationWorkbenchContext context, {
  String? profileId,
}) {
  final origin = context.workspace(request.originWorkspaceId);
  final project = context.project(request.projectId ?? origin?.projectId);
  final sectionId = request.sectionId ?? origin?.sectionId;
  var draft = AutomationDraft(originWorkspaceId: request.originWorkspaceId);
  final seeded = <AutomationDraftField, String>{};
  if (origin != null) {
    draft = draft.withTargetType(AutomationTargetType.freshTab);
    seeded[.workspaceId] = origin.id;
  } else if (project != null &&
      project.isGitRepository &&
      !project.isRemoteOnly) {
    draft = draft.withTargetType(AutomationTargetType.worktree);
    seeded[.projectId] = project.id;
  }
  return draft.copyWith(
    targetFields: <AutomationDraftField, String>{
      ...seeded,
      .agentProfileId: ?profileId,
      .workspaceSectionId: ?sectionId,
    },
    fromContext: seeded.keys.toSet(),
  );
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
