import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/chips/alera_property_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/presentation/automation_popover_chip.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_destination_picker.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_reuse_policy_popover.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_schedule_popover.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Schedule, destination, agent, reuse and options of the draft, one chip
/// each. A chip is outlined in red while its property blocks saving.
class const AutomationComposerChips({
  required final AutomationComposerControllerProvider provider,
  required final VoidCallback onShowOptions,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagged = ref.watch(
      provider.select((state) => state.flaggedProperties),
    );
    final draft = ref.watch(provider.select((state) => state.draft));
    final reuse =
        ref.watch(automationRuntimeCapabilitiesProvider).value?.reuse ?? false;
    final options = draft.customizedOptionCount;
    return Wrap(
      spacing: AleraTokens.space6,
      runSpacing: AleraTokens.space6,
      children: <Widget>[
        AutomationScheduleChip(
          provider: provider,
          hasError: flagged.contains(AutomationComposerProperty.schedule),
        ),
        AutomationDestinationChip(
          provider: provider,
          hasError: flagged.contains(AutomationComposerProperty.destination),
        ),
        if (draft.targetType != AutomationTargetType.existingTab)
          _AgentChip(
            provider: provider,
            hasError: flagged.contains(AutomationComposerProperty.agent),
          ),
        if (reuse)
          AutomationReusePolicyChip(
            provider: provider,
            hasError: flagged.contains(AutomationComposerProperty.reuse),
          ),
        AleraPropertyChip(
          icon: AleraIcons.tune,
          value: options == 0 ? 'Options' : 'Options · $options',
          tooltip: 'Show Options',
          hasError: flagged.contains(AutomationComposerProperty.options),
          onTap: onShowOptions,
        ),
      ],
    );
  }
}

class const _AgentChip({
  required final AutomationComposerControllerProvider provider,
  required final bool hasError,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(provider.select((state) => state.draft));
    final names = ref.watch(automationWorkbenchContextProvider);
    final profileId = draft.field(.agentProfileId);
    return AutomationPopoverChip(
      icon: AleraIcons.agent,
      value: profileId == null ? 'Choose Agent' : names.profileName(profileId),
      tooltip: 'Agent Profile',
      hasError: hasError,
      fromContext: draft.fromContext.contains(
        AutomationDraftField.agentProfileId,
      ),
      width: AleraTokens.contextMenuWidth,
      builder: (context, close) => Padding(
        padding: const EdgeInsets.all(AleraTokens.space4),
        child: names.profiles.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(AleraTokens.space8),
                child: Text(
                  'No agent profiles yet. Add one in Settings.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AleraTokens.foregroundMuted),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    for (final profile in names.profiles)
                      AleraMenuItem(
                        label: profile.name,
                        selected: profile.id == profileId,
                        onTap: () {
                          ref
                              .read(provider.notifier)
                              .update(
                                (current) => current.withTargetField(
                                  .agentProfileId,
                                  profile.id,
                                ),
                              );
                          close();
                        },
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
