import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/forms/alera_date_time_field.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/forms/alera_time_of_day_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera/src/features/automations/presentation/automation_popover_chip.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const List<int> _everyHoursChoices = <int>[1, 2, 3, 4, 6, 8, 12];

/// When the automation runs, edited in a popover.
class const AutomationScheduleChip({
  required final AutomationComposerControllerProvider provider,
  required final bool hasError,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(provider.select((state) => state.draft));
    return AutomationPopoverChip(
      icon: AleraIcons.schedule,
      value: draft.schedule.describe(timezone: draft.timezone),
      tooltip: 'Schedule',
      hasError: hasError,
      width: AleraTokens.dialogWidth,
      builder: (context, close) => _ScheduleEditor(provider: provider),
    );
  }
}

class _ScheduleEditor extends ConsumerStatefulWidget {
  const _ScheduleEditor({required this.provider});

  final AutomationComposerControllerProvider provider;

  @override
  ConsumerState<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends ConsumerState<_ScheduleEditor> {
  late final TextEditingController _cron = TextEditingController(
    text: ref.read(widget.provider).draft.schedule.customCron,
  );

  @override
  void dispose() {
    _cron.dispose();
    super.dispose();
  }

  void _change(
    AutomationSchedulePreset Function(AutomationSchedulePreset schedule) edit,
  ) => ref
      .read(widget.provider.notifier)
      .update((draft) => draft.copyWith(schedule: edit(draft.schedule)));

  Widget _time(AutomationSchedulePreset schedule) => AleraTimeOfDayField(
    labelText: 'At',
    hour: schedule.hour,
    minute: schedule.minute,
    onChanged: (hour, minute) =>
        _change((value) => value.copyWith(hour: hour, minute: minute)),
  );

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(widget.provider.select((state) => state.draft));
    final schedule = draft.schedule;
    final error = schedule.localError;
    final theme = Theme.of(context);
    final fields = <Widget>[
      AleraDropdownField<AutomationScheduleKind>(
        labelText: 'Repeat',
        value: schedule.kind,
        entries: <AleraDropdownFieldEntry<AutomationScheduleKind>>[
          for (final kind in AutomationScheduleKind.values)
            AleraDropdownFieldEntry(value: kind, label: kind.label),
        ],
        onChanged: (kind) => _change((value) => value.copyWith(kind: kind)),
      ),
      ...switch (schedule.kind) {
        AutomationScheduleKind.weekdays ||
        AutomationScheduleKind.daily => <Widget>[_time(schedule)],
        AutomationScheduleKind.weekly => <Widget>[
          Wrap(
            spacing: AleraTokens.space6,
            runSpacing: AleraTokens.space6,
            children: <Widget>[
              for (final (day, label) in automationWeekdays)
                AleraChip(
                  label: label,
                  leading: schedule.weekdays.contains(day)
                      ? AleraIcons.check
                      : null,
                  tooltip: schedule.weekdays.contains(day)
                      ? 'Skip $label'
                      : 'Run On $label',
                  onTap: () => _change(
                    (value) => value.copyWith(
                      weekdays: value.weekdays.contains(day)
                          ? (Set<int>.of(value.weekdays)..remove(day))
                          : <int>{...value.weekdays, day},
                    ),
                  ),
                ),
            ],
          ),
          _time(schedule),
        ],
        AutomationScheduleKind.everyHours => <Widget>[
          AleraDropdownField<int>(
            labelText: 'Every',
            value: _everyHoursChoices.contains(schedule.everyHours)
                ? schedule.everyHours
                : null,
            entries: <AleraDropdownFieldEntry<int>>[
              for (final hours in _everyHoursChoices)
                AleraDropdownFieldEntry(
                  value: hours,
                  label: hours == 1 ? '1 Hour' : '$hours Hours',
                ),
            ],
            onChanged: (hours) =>
                _change((value) => value.copyWith(everyHours: hours)),
          ),
        ],
        AutomationScheduleKind.once => <Widget>[
          AleraDateTimeField(
            labelText: 'At',
            value: schedule.onceAt,
            firstDate: DateTime.now(),
            onChanged: (value) {
              if (value != null) {
                _change((current) => current.copyWith(onceAt: value));
              }
            },
          ),
        ],
        AutomationScheduleKind.custom => <Widget>[
          AleraTextField(
            controller: _cron,
            labelText: 'Cron Expression',
            hintText: '0 9 * * 1-5',
            errorText: error,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (value) =>
                _change((current) => current.copyWith(customCron: value)),
          ),
        ],
      },
      if (!schedule.isOneTime)
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
          onChanged: (zone) => ref
              .read(widget.provider.notifier)
              .update((current) => current.copyWith(timezone: zone)),
        ),
      if (error != null && schedule.kind != AutomationScheduleKind.custom)
        Text(
          error,
          style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.error),
        ),
      Text(
        schedule.describe(timezone: draft.timezone),
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: <Widget>[
          for (final (index, field) in fields.indexed) ...<Widget>[
            if (index > 0) const SizedBox(height: AleraTokens.space12),
            field,
          ],
        ],
      ),
    );
  }
}
