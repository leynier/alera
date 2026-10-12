import 'dart:async';

import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_controller.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_agent_reuse_sheets.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_composer_sheet.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_destination_sheet.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_schedule_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Schedule, destination, agent, reuse and options of the draft, one row
/// each. Each opens its own sheet; a row is marked in red while its property
/// blocks saving.
class const MobileAutomationPropertyRows({
  required final MobileAutomationComposerControllerProvider provider,
  required final String hostId,
  required final VoidCallback onShowOptions,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final draft = state.draft;
    final names =
        ref.watch(mobileAutomationContextProvider(hostId)).value ??
        const MobileAutomationContext();
    final reuse =
        ref
            .watch(mobileAutomationRepositoryProvider(hostId))
            .value
            ?.supportsReuse ??
        false;
    final profileId = draft.field(.agentProfileId);
    final fixedReuse = automationReusePolicyIsFixed(draft.targetType);
    final bound = state.editing?.boundTarget != null;
    final options = draft.customizedOptionCount;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        MobileAutomationPropertyRow(
          icon: AleraIcons.schedule,
          label: 'Schedule',
          value: draft.schedule.describe(timezone: draft.timezone),
          problem: state.problemFor(.schedule),
          onTap: () => unawaited(
            showMobileAutomationComposerSheet(
              context,
              title: 'Schedule',
              builder: (_, _) =>
                  MobileAutomationScheduleEditor(provider: provider),
            ),
          ),
        ),
        MobileAutomationPropertyRow(
          icon: AleraIcons.workspaceMain,
          label: 'Destination',
          value: draft.targetType == null
              ? 'Choose Destination'
              : automationTargetSummary(
                  draft.withTargetField(.agentProfileId, null),
                  names,
                ),
          problem: state.problemFor(.destination),
          fromContext: draft.fromContext.any(
            (field) => field != AutomationDraftField.agentProfileId,
          ),
          onTap: () => unawaited(
            showMobileAutomationComposerSheet(
              context,
              title: 'Destination',
              builder: (_, close) => MobileAutomationDestinationEditor(
                provider: provider,
                hostId: hostId,
                close: close,
              ),
            ),
          ),
        ),
        if (draft.targetType != AutomationTargetType.existingTab)
          MobileAutomationPropertyRow(
            icon: AleraIcons.agent,
            label: 'Agent',
            value: profileId == null
                ? 'Choose Agent'
                : names.profileName(profileId),
            problem: state.problemFor(.agent),
            onTap: () => unawaited(
              showMobileAutomationAgentSheet(context, ref, provider, names),
            ),
          ),
        if (reuse)
          MobileAutomationPropertyRow(
            icon: AleraIcons.link,
            label: 'Reuse',
            value: fixedReuse
                ? automationContinuesConversationLabel
                : draft.reusePolicy.label,
            problem: state.problemFor(.reuse),
            onTap: fixedReuse && !bound
                ? null
                : () => unawaited(
                    showMobileAutomationReuseSheet(context, provider, names),
                  ),
          ),
        MobileAutomationPropertyRow(
          icon: AleraIcons.tune,
          label: 'Options',
          value: options == 0 ? 'Defaults' : '$options Changed',
          problem: state.problemFor(.options),
          onTap: onShowOptions,
        ),
      ],
    );
  }
}
