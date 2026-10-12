import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_controller.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_reliability_options.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_schedule_limits_options.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_workspace_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The options that apply to the current draft, grouped. Groups and fields
/// that do not apply to the schedule, destination or reuse policy are left
/// out rather than disabled.
class const MobileAutomationComposerOptions({
  required final MobileAutomationComposerControllerProvider provider,
  required final String hostId,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(provider.select((state) => state.draft));
    final groups = <(String, Widget)>[
      if (draft.offersScheduleLimits)
        (
          'Schedule Limits',
          MobileAutomationScheduleLimitsOptions(provider: provider),
        ),
      ('Reliability', MobileAutomationReliabilityOptions(provider: provider)),
      if (draft.offersWorkspaceOptions)
        (
          'Workspace',
          MobileAutomationWorkspaceOptions(provider: provider, hostId: hostId),
        ),
      (
        'Notifications',
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notify On Success'),
          subtitle: const Text(
            'Also notify paired phones when a run succeeds.',
          ),
          value: draft.notifyOnSuccess,
          onChanged: (value) => ref
              .read(provider.notifier)
              .update((current) => current.copyWith(notifyOnSuccess: value)),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final (title, child) in groups) ...<Widget>[
          AleraSectionHeader(
            label: title,
            padding: const EdgeInsets.only(
              top: AleraTokens.spaceSm,
              bottom: AleraTokens.spaceSm,
            ),
          ),
          child,
          const SizedBox(height: AleraTokens.spaceMd),
        ],
      ],
    );
  }
}

/// A policy picker shared by the option groups.
class const MobileAutomationPolicyField({
  required final String label,
  required final String value,
  required final List<String> options,
  required final ValueChanged<String> onChanged,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AleraDropdownField<String>(
    labelText: label,
    value: value,
    entries: <AleraDropdownFieldEntry<String>>[
      for (final option in options)
        AleraDropdownFieldEntry(
          value: option,
          label: automationPolicyLabel(option),
        ),
    ],
    onChanged: onChanged,
  );
}

/// Option fields stacked with the standard gap.
class const MobileAutomationOptionFields({
  required final List<Widget> children,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: <Widget>[
      for (final (index, child) in children.indexed) ...<Widget>[
        if (index > 0) const SizedBox(height: AleraTokens.spaceMd),
        child,
      ],
    ],
  );
}
