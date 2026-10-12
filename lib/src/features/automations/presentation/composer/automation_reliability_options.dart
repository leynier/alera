import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_duration_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_options.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overlap, inactivity, retries and the precheck. Durations are edited in
/// human units and sent in seconds; values outside the runtime's limits show
/// its message instead of being clamped.
class AutomationReliabilityOptions extends ConsumerStatefulWidget {
  const AutomationReliabilityOptions({super.key, required this.provider});

  final AutomationComposerControllerProvider provider;

  @override
  ConsumerState<AutomationReliabilityOptions> createState() =>
      _AutomationReliabilityOptionsState();
}

class _AutomationReliabilityOptionsState
    extends ConsumerState<AutomationReliabilityOptions> {
  late final TextEditingController _precheck = TextEditingController(
    text: ref.read(widget.provider).draft.precheckCommand,
  );

  @override
  void dispose() {
    _precheck.dispose();
    super.dispose();
  }

  void _update(AutomationDraft Function(AutomationDraft draft) change) =>
      ref.read(widget.provider.notifier).update(change);

  void _setNumber(AutomationNumericField field, int value) => _update(
    (current) => current.copyWith(
      numbers: <AutomationNumericField, String>{
        ...current.numbers,
        field: '$value',
      },
    ),
  );

  Widget _duration(
    AutomationDraft draft,
    AutomationNumericField field,
    List<AleraDurationUnit> units,
  ) => AleraDurationField(
    labelText: field.label,
    seconds: int.tryParse(draft.number(field)) ?? field.defaultValue,
    units: units,
    errorText: draft.numberErrors[field],
    onChanged: (seconds) => _setNumber(field, seconds),
  );

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(widget.provider.select((state) => state.draft));
    const retries = AutomationNumericField.retryMaxAttempts;
    final attempts = int.tryParse(draft.number(retries));
    return AutomationOptionFields(
      children: <Widget>[
        AutomationPolicyField(
          label: 'When Runs Overlap',
          value: draft.overlapPolicy,
          options: automationOverlapPolicies,
          onChanged: (value) =>
              _update((current) => current.copyWith(overlapPolicy: value)),
        ),
        _duration(draft, .inactivityTimeoutSeconds, const <AleraDurationUnit>[
          .seconds,
          .minutes,
          .hours,
        ]),
        AleraDropdownField<int>(
          labelText: retries.label,
          value: attempts,
          entries: <AleraDropdownFieldEntry<int>>[
            for (var count = retries.min; count <= retries.max; count++)
              AleraDropdownFieldEntry(
                value: count,
                label: count == 1 ? '1 Launch' : '$count Launches',
              ),
          ],
          onChanged: (value) => _setNumber(retries, value),
        ),
        AleraTextField(
          controller: _precheck,
          labelText: 'Precheck Command',
          hintText: 'Optional. A non-zero exit skips the run.',
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (value) =>
              _update((current) => current.copyWith(precheckCommand: value)),
        ),
        if (draft.precheckCommand.trim().isNotEmpty)
          _duration(draft, .precheckTimeoutSeconds, const <AleraDurationUnit>[
            .seconds,
            .minutes,
          ]),
      ],
    );
  }
}
