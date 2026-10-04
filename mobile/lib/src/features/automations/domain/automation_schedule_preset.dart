import 'package:alera_mobile/src/features/automations/domain/automation_json_fields.dart';

enum AutomationScheduleKind(final String label) {
  weekdays('Weekdays At'),
  daily('Daily At'),
  weekly('Weekly On Days At'),
  everyHours('Every N Hours'),
  once('Once At'),
  custom('Custom Cron'),
}

/// Weekday numbers follow cron: 0 is Sunday, 1 is Monday.
const List<(int, String)> automationWeekdays = <(int, String)>[
  (1, 'Mon'),
  (2, 'Tue'),
  (3, 'Wed'),
  (4, 'Thu'),
  (5, 'Fri'),
  (6, 'Sat'),
  (0, 'Sun'),
];

/// A schedule as the authoring flow edits it. Every preset compiles to the
/// runtime's existing `recurring` cron or `oneTime` JSON; nothing new reaches
/// the wire.
class const AutomationSchedulePreset({
  required final AutomationScheduleKind kind,
  final int hour = 9,
  final int minute = 0,
  final Set<int> weekdays = const <int>{1},
  final int everyHours = 4,
  final DateTime? onceAt,
  final String customCron = '',
}) {
  static const AutomationSchedulePreset initial = AutomationSchedulePreset(
    kind: AutomationScheduleKind.weekdays,
  );

  /// Reads a persisted schedule back into the preset that produced it, or a
  /// custom cron when the expression is not one of ours.
  factory fromSchedule(JsonMap schedule) {
    final oneTime = schedule['oneTime'];
    if (oneTime is Map) {
      final at = automationJsonDate(oneTime['at']);
      return AutomationSchedulePreset(
        kind: AutomationScheduleKind.once,
        onceAt: at?.toLocal(),
      );
    }
    final recurring = automationJsonMap(schedule['recurring']);
    final cron = automationJsonString(recurring['cron']).trim();
    return automationPresetFromCron(cron) ??
        AutomationSchedulePreset(
          kind: AutomationScheduleKind.custom,
          customCron: cron,
        );
  }

  AutomationSchedulePreset copyWith({
    AutomationScheduleKind? kind,
    int? hour,
    int? minute,
    Set<int>? weekdays,
    int? everyHours,
    DateTime? onceAt,
    String? customCron,
  }) => AutomationSchedulePreset(
    kind: kind ?? this.kind,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    weekdays: weekdays ?? this.weekdays,
    everyHours: everyHours ?? this.everyHours,
    onceAt: onceAt ?? this.onceAt,
    customCron: customCron ?? this.customCron,
  );

  bool get isOneTime => kind == AutomationScheduleKind.once;

  String get cron => switch (kind) {
    AutomationScheduleKind.weekdays => '$minute $hour * * 1-5',
    AutomationScheduleKind.daily => '$minute $hour * * *',
    AutomationScheduleKind.weekly =>
      '$minute $hour * * ${(weekdays.toList()..sort()).join(',')}',
    AutomationScheduleKind.everyHours => '$minute */$everyHours * * *',
    AutomationScheduleKind.custom => customCron.trim(),
    AutomationScheduleKind.once => '',
  };

  /// Inline problems the user can fix before the runtime validates.
  String? get localError => switch (kind) {
    AutomationScheduleKind.weekly when weekdays.isEmpty =>
      'Choose at least one day.',
    AutomationScheduleKind.everyHours when everyHours < 1 || everyHours > 23 =>
      'Choose between 1 and 23 hours.',
    AutomationScheduleKind.once when onceAt == null =>
      'Choose a date and time.',
    AutomationScheduleKind.custom
        when customCron.trim().split(RegExp(r'\s+')).length != 5 =>
      'Use five fields: minute, hour, day of month, month and day of week.',
    _ => null,
  };

  JsonMap toSchedule({String? timezone, JsonMap bounds = const {}}) {
    final zone = timezone?.trim();
    if (isOneTime) {
      return <String, Object?>{
        'oneTime': <String, Object?>{
          'at': onceAt?.toUtc().toIso8601String(),
          if (zone != null && zone.isNotEmpty) 'timezone': zone,
        },
      };
    }
    return <String, Object?>{
      'recurring': <String, Object?>{
        'cron': cron,
        if (zone != null && zone.isNotEmpty) 'timezone': zone,
        ...bounds,
      },
    };
  }

  String describe({String? timezone}) {
    final time = automationClockLabel(hour, minute);
    final base = switch (kind) {
      AutomationScheduleKind.weekdays => 'Weekdays at $time',
      AutomationScheduleKind.daily => 'Daily at $time',
      AutomationScheduleKind.weekly =>
        '${automationWeekdayList(weekdays)} at $time',
      AutomationScheduleKind.everyHours =>
        everyHours == 1
            ? 'Every hour at :${minute.toString().padLeft(2, '0')}'
            : 'Every $everyHours hours',
      AutomationScheduleKind.once =>
        onceAt == null ? 'Once' : 'Once on ${automationDateTimeLabel(onceAt!)}',
      AutomationScheduleKind.custom => 'Cron $customCron',
    };
    final zone = timezone?.trim();
    return zone == null || zone.isEmpty || isOneTime ? base : '$base · $zone';
  }
}

AutomationSchedulePreset? automationPresetFromCron(String cron) {
  final fields = cron.split(RegExp(r'\s+'));
  if (fields.length != 5) return null;
  final minute = int.tryParse(fields[0]);
  if (minute == null || minute < 0 || minute > 59) return null;
  final [_, hourField, day, month, weekday] = fields;
  if (day != '*' || month != '*') return null;
  final everyMatch = RegExp(r'^\*/(\d{1,2})$').firstMatch(hourField);
  if (everyMatch != null && weekday == '*') {
    return AutomationSchedulePreset(
      kind: AutomationScheduleKind.everyHours,
      minute: minute,
      everyHours: int.parse(everyMatch.group(1)!),
    );
  }
  final hour = int.tryParse(hourField);
  if (hour == null || hour < 0 || hour > 23) return null;
  if (weekday == '1-5') {
    return AutomationSchedulePreset(
      kind: AutomationScheduleKind.weekdays,
      hour: hour,
      minute: minute,
    );
  }
  if (weekday == '*') {
    return AutomationSchedulePreset(
      kind: AutomationScheduleKind.daily,
      hour: hour,
      minute: minute,
    );
  }
  final days = <int>{};
  for (final part in weekday.split(',')) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 7) return null;
    days.add(value == 7 ? 0 : value);
  }
  return AutomationSchedulePreset(
    kind: AutomationScheduleKind.weekly,
    hour: hour,
    minute: minute,
    weekdays: days,
  );
}

/// Human description of a persisted schedule, used in lists and headers.
String automationScheduleDescription(JsonMap schedule) {
  final details = automationJsonMap(
    schedule['recurring'] ?? schedule['oneTime'],
  );
  return AutomationSchedulePreset.fromSchedule(schedule)
      .describe(timezone: automationJsonOptionalString(details['timezone']));
}

String automationClockLabel(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

String automationWeekdayList(Set<int> days) {
  final names = <String>[
    for (final (value, label) in automationWeekdays)
      if (days.contains(value)) label,
  ];
  return names.isEmpty ? 'No days' : names.join(', ');
}

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String automationDateTimeLabel(DateTime moment) {
  final local = moment.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${local.year} '
      '${automationClockLabel(local.hour, local.minute)}';
}
