import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_reliability_options.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_schedule_limits_options.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_workspace_options.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The options that apply to the current draft, grouped. Groups and fields
/// that do not apply to the schedule, destination or reuse policy are left
/// out rather than disabled.
class const AutomationComposerOptions({
  required final AutomationComposerControllerProvider provider,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(provider.select((state) => state.draft));
    final groups = <(String, Widget)>[
      if (draft.offersScheduleLimits)
        (
          'Schedule Limits',
          AutomationScheduleLimitsOptions(provider: provider),
        ),
      ('Reliability', AutomationReliabilityOptions(provider: provider)),
      if (draft.offersWorkspaceOptions)
        ('Workspace', AutomationWorkspaceOptions(provider: provider)),
      (
        'Notifications',
        AleraSettingRow(
          title: 'Notify On Success',
          description: 'Also notify paired phones when a run succeeds.',
          child: Align(
            alignment: Alignment.centerRight,
            child: Switch(
              value: draft.notifyOnSuccess,
              onChanged: (value) => ref
                  .read(provider.notifier)
                  .update(
                    (current) => current.copyWith(notifyOnSuccess: value),
                  ),
            ),
          ),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final (title, child) in groups) ...<Widget>[
          AleraSectionHeader(label: title),
          child,
          const SizedBox(height: AleraTokens.space12),
        ],
      ],
    );
  }
}

/// A policy picker shared by the option groups.
class const AutomationPolicyField({
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
class const AutomationOptionFields({
  required final List<Widget> children,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: <Widget>[
      for (final (index, child) in children.indexed) ...<Widget>[
        if (index > 0) const SizedBox(height: AleraTokens.space12),
        child,
      ],
    ],
  );
}
