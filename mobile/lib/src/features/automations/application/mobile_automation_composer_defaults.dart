import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_automation_composer_defaults.g.dart';

/// The agent profile the last saved automation on [hostId] used while the
/// app runs, so the next one starts with it.
@Riverpod(keepAlive: true)
class MobileAutomationLastAgentProfile
    extends _$MobileAutomationLastAgentProfile {
  @override
  String? build(String hostId) => null;

  void remember(String? id) {
    if (id != null && id.isNotEmpty) state = id;
  }
}

/// The starting draft of a new automation opened from [originWorkspaceId]
/// (a workspace's tab menu) or from the catalog. The shared rules in
/// [seedAutomationDraft] decide what is seeded.
AutomationDraft seedMobileAutomationDraft(
  MobileAutomationContext context, {
  String? originWorkspaceId,
  String? lastProfileId,
}) {
  final origin = context.workspace(originWorkspaceId);
  return seedAutomationDraft(
    AutomationComposerOrigin(
      originWorkspaceId: originWorkspaceId,
      workspaceId: origin?.id,
      sectionId: origin?.sectionId,
      profileId: automationPreferredProfileId(
        context.profiles.map((profile) => profile.id),
        lastUsed: lastProfileId,
      ),
    ),
  );
}
