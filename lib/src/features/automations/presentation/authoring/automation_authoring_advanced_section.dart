import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/automations/application/automation_authoring_controller.dart';
import 'package:alera/src/features/automations/domain/automation_draft.dart';
import 'package:alera/src/features/automations/domain/automation_field_bounds.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rarely needed settings, collapsed by default. Numbers use the runtime's
/// exact limits and show an inline error rather than being clamped.
class AutomationAdvancedSection extends ConsumerStatefulWidget {
  const AutomationAdvancedSection({
    super.key,
    required this.provider,
    this.initiallyExpanded = false,
  });

  final AutomationAuthoringControllerProvider provider;
  final bool initiallyExpanded;

  @override
  ConsumerState<AutomationAdvancedSection> createState() =>
      _AutomationAdvancedSectionState();
}

class _AutomationAdvancedSectionState
    extends ConsumerState<AutomationAdvancedSection> {
  late final Map<AutomationNumericField, TextEditingController> _numbers;
  late final TextEditingController _precheck;
  late final TextEditingController _startAt;
  late final TextEditingController _endAt;
  late final TextEditingController _nameTemplate;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(widget.provider).draft;
    _numbers = <AutomationNumericField, TextEditingController>{
      for (final field in AutomationNumericField.values)
        field: TextEditingController(text: initial.number(field)),
    };
    _precheck = TextEditingController(text: initial.precheckCommand);
    _startAt = TextEditingController(text: initial.startAt);
    _endAt = TextEditingController(text: initial.endAt);
    _nameTemplate = TextEditingController(text: initial.nameTemplate);
  }

  @override
  void dispose() {
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    _precheck.dispose();
    _startAt.dispose();
    _endAt.dispose();
    _nameTemplate.dispose();
    super.dispose();
  }

  void _update(AutomationDraft Function(AutomationDraft draft) change) =>
      ref.read(widget.provider.notifier).update(change);

  Widget _number(AutomationDraft draft, AutomationNumericField field) {
    final errors = draft.numberErrors;
    return AleraTextField(
      controller: _numbers[field],
      labelText: field == AutomationNumericField.maxScheduledRuns
          ? '${field.label} (Optional)'
          : '${field.label} (${field.min}-${field.max} ${field.unit})',
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      errorText: errors[field],
      onChanged: (value) => _update(
        (current) => current.copyWith(
          numbers: <AutomationNumericField, String>{
            ...current.numbers,
            field: value,
          },
        ),
      ),
    );
  }

  Widget _policy(
    String label,
    String value,
    List<String> options,
    AutomationDraft Function(AutomationDraft draft, String value) apply,
  ) => AleraDropdownField<String>(
    labelText: label,
    value: value,
    entries: <AleraDropdownFieldEntry<String>>[
      for (final option in options)
        AleraDropdownFieldEntry(
          value: option,
          label: automationPolicyLabel(option),
        ),
    ],
    onChanged: (next) => _update((current) => apply(current, next)),
  );

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(widget.provider).draft;
    final usesWorkspaceName =
        draft.targetType == AutomationTargetType.managedWorkspace ||
        draft.targetType == AutomationTargetType.projectWorktree ||
        draft.targetType == AutomationTargetType.projectCheckout;
    const gap = SizedBox(height: AleraTokens.space12);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: widget.initiallyExpanded,
      title: const Text('Advanced'),
      subtitle: const Text(
        'Run rules, limits, cleanup, notifications and schedule bounds.',
      ),
      childrenPadding: const EdgeInsets.only(bottom: AleraTokens.space12),
      children: <Widget>[
        _policy(
          'Missed Schedules',
          draft.misfirePolicy,
          automationMisfirePolicies,
          (current, value) => current.copyWith(misfirePolicy: value),
        ),
        gap,
        _policy(
          'When Runs Overlap',
          draft.overlapPolicy,
          automationOverlapPolicies,
          (current, value) => current.copyWith(overlapPolicy: value),
        ),
        gap,
        if (draft.targetType !=
            AutomationTargetType.projectCheckout) ...<Widget>[
          _policy(
            'Workspace Setup',
            draft.setupPolicy,
            automationSetupPolicies,
            (current, value) => current.copyWith(setupPolicy: value),
          ),
          gap,
        ],
        _policy(
          'Cleanup',
          draft.cleanupPolicy,
          automationCleanupPolicies,
          (current, value) => current.copyWith(cleanupPolicy: value),
        ),
        gap,
        AleraTextField(
          controller: _precheck,
          labelText: 'Precheck Command (Optional)',
          hintText: 'A non-zero exit skips the run.',
          onChanged: (value) =>
              _update((current) => current.copyWith(precheckCommand: value)),
        ),
        gap,
        if (usesWorkspaceName) ...<Widget>[
          AleraTextField(
            controller: _nameTemplate,
            labelText: 'Workspace Name Template',
            onChanged: (value) =>
                _update((current) => current.copyWith(nameTemplate: value)),
          ),
          gap,
        ],
        for (final field in AutomationNumericField.values) ...<Widget>[
          _number(draft, field),
          gap,
        ],
        AleraTextField(
          controller: _startAt,
          labelText: 'Start At (Optional, ISO-8601)',
          onChanged: (value) =>
              _update((current) => current.copyWith(startAt: value)),
        ),
        gap,
        AleraTextField(
          controller: _endAt,
          labelText: 'End At (Optional, ISO-8601)',
          onChanged: (value) =>
              _update((current) => current.copyWith(endAt: value)),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notify On Success'),
          subtitle: const Text(
            'Also notify paired phones when a run succeeds.',
          ),
          value: draft.notifyOnSuccess,
          onChanged: (value) =>
              _update((current) => current.copyWith(notifyOnSuccess: value)),
        ),
      ],
    );
  }
}
