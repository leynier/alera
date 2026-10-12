import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/domain/automation_authoring_request.dart';
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

/// The starting draft of a new automation, seeded from where it was started
/// (see [seedAutomationDraft]). Only a Git project on this computer seeds a
/// worktree; a remote-only project waits for its folders instead.
AutomationDraft seedAutomationComposerDraft(
  AutomationAuthoringRequest request,
  AutomationWorkbenchContext context, {
  String? profileId,
}) {
  final origin = context.workspace(request.originWorkspaceId);
  final project = context.project(request.projectId ?? origin?.projectId);
  return seedAutomationDraft(
    AutomationComposerOrigin(
      originWorkspaceId: request.originWorkspaceId,
      workspaceId: origin?.id,
      worktreeProjectId:
          project != null && project.isGitRepository && !project.isRemoteOnly
          ? project.id
          : null,
      sectionId: request.sectionId ?? origin?.sectionId,
      profileId: profileId,
    ),
  );
}
