import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_authoring_controller.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_draft.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_field_bounds.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_timezones.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_lines.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MobileWhatStep extends ConsumerStatefulWidget {
  const MobileWhatStep({super.key, required this.provider});

  final MobileAutomationAuthoringControllerProvider provider;

  @override
  ConsumerState<MobileWhatStep> createState() => _MobileWhatStepState();
}

class _MobileWhatStepState extends ConsumerState<MobileWhatStep> {
  late final TextEditingController _prompt;
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(widget.provider).draft;
    _prompt = TextEditingController(text: draft.promptTemplate);
    _name = TextEditingController(text: draft.name);
  }

  @override
  void dispose() {
    _prompt.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);
    final controller = ref.read(widget.provider.notifier);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraTextField(
          controller: _prompt,
          labelText: 'What Should The Agent Do?',
          minLines: 5,
          maxLines: 10,
          errorText: state.showErrors ? state.draft.whatError : null,
          onChanged: (value) => controller.update(
            (draft) => draft.copyWith(promptTemplate: value),
          ),
        ),
        const SizedBox(height: AleraTokens.spaceMd),
        AleraTextField(
          controller: _name,
          labelText: 'Name',
          hintText: state.draft.effectiveName,
          onChanged: (value) =>
              controller.update((draft) => draft.copyWith(name: value)),
        ),
      ],
    );
  }
}

class MobileWhenStep extends ConsumerStatefulWidget {
  const MobileWhenStep({super.key, required this.provider});

  final MobileAutomationAuthoringControllerProvider provider;

  @override
  ConsumerState<MobileWhenStep> createState() => _MobileWhenStepState();
}

class _MobileWhenStepState extends ConsumerState<MobileWhenStep> {
  late final TextEditingController _cron;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _cron = TextEditingController(
      text: ref.read(widget.provider).draft.schedule.customCron,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cron.dispose();
    super.dispose();
  }

  void _change(
    AutomationSchedulePreset Function(AutomationSchedulePreset) edit,
  ) {
    ref
        .read(widget.provider.notifier)
        .update((draft) => draft.copyWith(schedule: edit(draft.schedule)));
    _debounce?.cancel();
    _debounce = Timer(
      AleraTokens.durationSlow,
      () => unawaited(ref.read(widget.provider.notifier).refreshPreview()),
    );
  }

  Future<void> _pickTime(AutomationSchedulePreset schedule) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: schedule.hour, minute: schedule.minute),
    );
    if (picked == null || !mounted) return;
    _change(
      (value) => value.copyWith(hour: picked.hour, minute: picked.minute),
    );
  }

  Future<void> _pickOnce(AutomationSchedulePreset schedule) async {
    final now = DateTime.now();
    final initial = schedule.onceAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    _change(
      (value) => value.copyWith(
        onceAt: DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);
    final draft = state.draft;
    final schedule = draft.schedule;
    final error = state.showErrors ? draft.whenError : null;
    final preview = state.preview;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraDropdownField<AutomationScheduleKind>(
          labelText: 'Repeat',
          value: schedule.kind,
          entries: <AleraDropdownFieldEntry<AutomationScheduleKind>>[
            for (final kind in AutomationScheduleKind.values)
              AleraDropdownFieldEntry(value: kind, label: kind.label),
          ],
          onChanged: (kind) => _change((value) => value.copyWith(kind: kind)),
        ),
        const SizedBox(height: AleraTokens.spaceMd),
        switch (schedule.kind) {
          AutomationScheduleKind.once => OutlinedButton(
            onPressed: () => unawaited(_pickOnce(schedule)),
            child: Text(
              schedule.onceAt == null
                  ? 'Choose Date And Time'
                  : automationDateTimeLabel(schedule.onceAt!),
            ),
          ),
          AutomationScheduleKind.custom => AleraTextField(
            controller: _cron,
            labelText: 'Five-Field Cron',
            errorText: error,
            onChanged: (value) =>
                _change((current) => current.copyWith(customCron: value)),
          ),
          AutomationScheduleKind.everyHours => AleraDropdownField<int>(
            labelText: 'Every',
            value: schedule.everyHours,
            entries: <AleraDropdownFieldEntry<int>>[
              for (final hours in const <int>[1, 2, 3, 4, 6, 8, 12])
                AleraDropdownFieldEntry(
                  value: hours,
                  label: hours == 1 ? '1 Hour' : '$hours Hours',
                ),
            ],
            onChanged: (hours) =>
                _change((value) => value.copyWith(everyHours: hours)),
          ),
          _ => OutlinedButton(
            onPressed: () => unawaited(_pickTime(schedule)),
            child: Text(
              'At ${automationClockLabel(schedule.hour, schedule.minute)}',
            ),
          ),
        },
        if (schedule.kind == AutomationScheduleKind.weekly)
          Wrap(
            spacing: AleraTokens.spaceXs,
            children: <Widget>[
              for (final (day, label) in automationWeekdays)
                FilterChip(
                  label: Text(label),
                  selected: schedule.weekdays.contains(day),
                  onSelected: (selected) => _change(
                    (value) => value.copyWith(
                      weekdays: selected
                          ? <int>{...value.weekdays, day}
                          : (Set<int>.of(value.weekdays)..remove(day)),
                    ),
                  ),
                ),
            ],
          ),
        if (error != null && schedule.kind != AutomationScheduleKind.custom)
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.error,
            ),
          ),
        if (!schedule.isOneTime) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceMd),
          AleraDropdownField<String?>(
            labelText: 'Time Zone',
            value: draft.timezone,
            hintText: 'Runtime Time Zone',
            filterable: true,
            entries: <AleraDropdownFieldEntry<String?>>[
              for (final zone in automationTimezoneChoices(draft.timezone))
                AleraDropdownFieldEntry(value: zone, label: zone),
            ],
            onChanged: (zone) {
              ref
                  .read(widget.provider.notifier)
                  .update((current) => current.copyWith(timezone: zone));
              unawaited(ref.read(widget.provider.notifier).refreshPreview());
            },
          ),
        ],
        const SizedBox(height: AleraTokens.spaceMd),
        Text(schedule.describe(timezone: draft.timezone)),
        if (preview != null && preview.errors.isNotEmpty)
          AleraNotice(message: preview.errors.first.message)
        else if (preview != null)
          for (final occurrence in preview.occurrences.take(3))
            Text(
              '${occurrence['localTime'] ?? occurrence['scheduledAt'] ?? ''}',
              style: theme.textTheme.bodySmall,
            ),
        const SizedBox(height: AleraTokens.spaceMd),
        Text(
          draft.misfirePolicy == 'skip'
              ? 'If the runtime is off at a scheduled time, that run is skipped. You can change this under Advanced in Review.'
              : 'Missed runs follow the Missed Schedules setting under Advanced in Review.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
    );
  }
}

class MobileReviewStep extends ConsumerStatefulWidget {
  const MobileReviewStep({
    super.key,
    required this.provider,
    required this.hostId,
  });

  final MobileAutomationAuthoringControllerProvider provider;
  final String hostId;

  @override
  ConsumerState<MobileReviewStep> createState() => _MobileReviewStepState();
}

class _MobileReviewStepState extends ConsumerState<MobileReviewStep> {
  late final Map<AutomationNumericField, TextEditingController> _numbers;
  late final TextEditingController _precheck;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(widget.provider).draft;
    _numbers = <AutomationNumericField, TextEditingController>{
      for (final field in AutomationNumericField.values)
        field: TextEditingController(text: draft.number(field)),
    };
    _precheck = TextEditingController(text: draft.precheckCommand);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(widget.provider.notifier).checkReadiness());
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    _precheck.dispose();
    super.dispose();
  }

  void _update(AutomationDraft Function(AutomationDraft draft) change) =>
      ref.read(widget.provider.notifier).update(change);

  Widget _policy(
    String label,
    String value,
    List<String> options,
    AutomationDraft Function(AutomationDraft draft, String value) apply,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.spaceMd),
    child: AleraDropdownField<String>(
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
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);
    final draft = state.draft;
    final names =
        ref.watch(mobileAutomationContextProvider(widget.hostId)).value ??
        const MobileAutomationContext();
    final readiness = state.readiness;
    final errors = draft.numberErrors;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final (label, value) in <(String, String)>[
          ('Name', draft.effectiveName),
          ('When', draft.schedule.describe(timezone: draft.timezone)),
          ('Where', mobileDraftTargetLine(draft, names)),
          if (names.workspace(draft.originWorkspaceId) case final origin?)
            ('Shown In', origin.name),
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            subtitle: Text(value),
          ),
        if (state.checking)
          const LinearProgressIndicator()
        else if (readiness != null && readiness.issues.isEmpty)
          const AleraNotice(message: 'Ready. The runtime found nothing to fix.')
        else if (readiness != null)
          for (final issue in readiness.issues)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
              child: AleraNotice(
                message: issue.action == null
                    ? issue.message
                    : '${issue.message} ${issue.action}',
              ),
            ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: errors.isNotEmpty,
          title: const Text('Advanced'),
          subtitle: const Text('Run rules, limits, cleanup and notifications.'),
          children: <Widget>[
            _policy(
              'Missed Schedules',
              draft.misfirePolicy,
              automationMisfirePolicies,
              (current, value) => current.copyWith(misfirePolicy: value),
            ),
            _policy(
              'When Runs Overlap',
              draft.overlapPolicy,
              automationOverlapPolicies,
              (current, value) => current.copyWith(overlapPolicy: value),
            ),
            _policy(
              'Cleanup',
              draft.cleanupPolicy,
              automationCleanupPolicies,
              (current, value) => current.copyWith(cleanupPolicy: value),
            ),
            AleraTextField(
              controller: _precheck,
              labelText: 'Precheck Command (Optional)',
              onChanged: (value) => _update(
                (current) => current.copyWith(precheckCommand: value),
              ),
            ),
            for (final field in AutomationNumericField.values)
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.spaceMd),
                child: AleraTextField(
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
                ),
              ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notify On Success'),
              subtitle: const Text(
                'Also notify paired phones when a run succeeds.',
              ),
              value: draft.notifyOnSuccess,
              onChanged: (value) => _update(
                (current) => current.copyWith(notifyOnSuccess: value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
