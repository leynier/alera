import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/design_system/forms/alera_date_time_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_controller.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_composer_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When a recurring schedule starts and stops, and what happens to the runs
/// missed while the runtime was off.
class MobileAutomationScheduleLimitsOptions extends ConsumerStatefulWidget {
  const MobileAutomationScheduleLimitsOptions({
    super.key,
    required this.provider,
  });

  final MobileAutomationComposerControllerProvider provider;

  @override
  ConsumerState<MobileAutomationScheduleLimitsOptions> createState() =>
      _MobileAutomationScheduleLimitsOptionsState();
}

class _MobileAutomationScheduleLimitsOptionsState
    extends ConsumerState<MobileAutomationScheduleLimitsOptions> {
  late final TextEditingController _maxRuns = TextEditingController(
    text: ref
        .read(widget.provider)
        .draft
        .number(AutomationNumericField.maxScheduledRuns),
  );

  @override
  void dispose() {
    _maxRuns.dispose();
    super.dispose();
  }

  void _update(AutomationDraft Function(AutomationDraft draft) change) =>
      ref.read(widget.provider.notifier).update(change);

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(widget.provider.select((state) => state.draft));
    DateTime? moment(String value) =>
        DateTime.tryParse(value.trim())?.toLocal();
    String stored(DateTime? value) => value?.toUtc().toIso8601String() ?? '';
    return MobileAutomationOptionFields(
      children: <Widget>[
        AleraDateTimeField(
          labelText: 'Starts',
          value: moment(draft.startAt),
          clearable: true,
          onChanged: (value) =>
              _update((current) => current.copyWith(startAt: stored(value))),
        ),
        AleraDateTimeField(
          labelText: 'Ends',
          value: moment(draft.endAt),
          clearable: true,
          onChanged: (value) =>
              _update((current) => current.copyWith(endAt: stored(value))),
        ),
        AleraTextField(
          controller: _maxRuns,
          labelText: 'Max Scheduled Runs',
          hintText: 'No limit',
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          errorText:
              draft.numberErrors[AutomationNumericField.maxScheduledRuns],
          onChanged: (value) => _update(
            (current) => current.copyWith(
              numbers: <AutomationNumericField, String>{
                ...current.numbers,
                .maxScheduledRuns: value,
              },
            ),
          ),
        ),
        MobileAutomationPolicyField(
          label: 'Missed Schedules',
          value: draft.misfirePolicy,
          options: automationMisfirePolicies,
          onChanged: (value) =>
              _update((current) => current.copyWith(misfirePolicy: value)),
        ),
      ],
    );
  }
}
