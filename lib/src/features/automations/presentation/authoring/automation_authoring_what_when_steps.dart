import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/automations/application/automation_authoring_controller.dart';
import 'package:alera/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:alera/src/features/automations/domain/automation_timezones.dart';
import 'package:alera/src/features/automations/presentation/authoring/automation_prompt_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AutomationWhatStep extends ConsumerStatefulWidget {
  const AutomationWhatStep({super.key, required this.provider});

  final AutomationAuthoringControllerProvider provider;

  @override
  ConsumerState<AutomationWhatStep> createState() => _AutomationWhatStepState();
}

class _AutomationWhatStepState extends ConsumerState<AutomationWhatStep> {
  late final AutomationTemplateTextController _prompt;
  late final TextEditingController _name;
  late final TextEditingController _description;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(widget.provider).draft;
    _prompt = AutomationTemplateTextController(text: draft.promptTemplate);
    _name = TextEditingController(text: draft.name);
    _description = TextEditingController(text: draft.description);
  }

  @override
  void dispose() {
    _prompt.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);
    final controller = ref.read(widget.provider.notifier);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AutomationPromptEditor(
          controller: _prompt,
          autofocus: true,
          errorText: state.showErrors ? state.draft.whatError : null,
          onChanged: (value) => controller.update(
            (draft) => draft.copyWith(promptTemplate: value),
          ),
        ),
        const SizedBox(height: AleraTokens.space12),
        AleraTextField(
          controller: _name,
          labelText: 'Name',
          hintText: state.draft.effectiveName,
          onChanged: (value) =>
              controller.update((draft) => draft.copyWith(name: value)),
        ),
        const SizedBox(height: AleraTokens.space12),
        AleraTextField(
          controller: _description,
          labelText: 'Description (Optional)',
          minLines: 2,
          maxLines: 4,
          onChanged: (value) =>
              controller.update((draft) => draft.copyWith(description: value)),
        ),
      ],
    );
  }
}

class AutomationWhenStep extends ConsumerStatefulWidget {
  const AutomationWhenStep({super.key, required this.provider});

  final AutomationAuthoringControllerProvider provider;

  @override
  ConsumerState<AutomationWhenStep> createState() => _AutomationWhenStepState();
}

class _AutomationWhenStepState extends ConsumerState<AutomationWhenStep> {
  late final TextEditingController _cron;
  Timer? _previewDebounce;

  @override
  void initState() {
    super.initState();
    _cron = TextEditingController(
      text: ref.read(widget.provider).draft.schedule.customCron,
    );
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _cron.dispose();
    super.dispose();
  }

  void _change(
    AutomationSchedulePreset Function(AutomationSchedulePreset) edit,
  ) {
    ref
        .read(widget.provider.notifier)
        .update((draft) => draft.copyWith(schedule: edit(draft.schedule)));
    _previewDebounce?.cancel();
    _previewDebounce = Timer(
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
    final theme = Theme.of(context);
    final error = state.showErrors ? draft.whenError : null;
    final preview = state.preview;
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
        const SizedBox(height: AleraTokens.space12),
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
            hintText: '0 9 * * 1-5',
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
        if (schedule.kind == AutomationScheduleKind.weekly) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          Wrap(
            spacing: AleraTokens.space6,
            runSpacing: AleraTokens.space6,
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
        ],
        if (error != null && schedule.kind != AutomationScheduleKind.custom)
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space8),
            child: Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.error,
              ),
            ),
          ),
        if (!schedule.isOneTime) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          AleraDropdownField<String?>(
            labelText: 'Time Zone',
            value: draft.timezone,
            filterable: true,
            filterHintText: 'Search Time Zones',
            hintText: 'Runtime Time Zone',
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
        const SizedBox(height: AleraTokens.space12),
        Text(
          draft.schedule.describe(timezone: draft.timezone),
          style: theme.textTheme.bodyMedium,
        ),
        if (preview != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          if (preview.errors.isNotEmpty)
            AleraInlineNotice(
              tone: .error,
              message: preview.errors.first.message,
            )
          else ...<Widget>[
            Text('Next Runs', style: theme.textTheme.labelMedium),
            for (final occurrence in preview.occurrences.take(3))
              Text(
                '${occurrence['localTime'] ?? occurrence['scheduledAt'] ?? ''}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ],
        const SizedBox(height: AleraTokens.space12),
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
