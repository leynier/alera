import 'package:alera/src/features/automations/domain/automation_schedule_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presets compile to the runtime cron and read back', () {
    const cases = <(AutomationSchedulePreset, String)>[
      (
        AutomationSchedulePreset(kind: .weekdays, hour: 9, minute: 30),
        '30 9 * * 1-5',
      ),
      (AutomationSchedulePreset(kind: .daily, hour: 18), '0 18 * * *'),
      (
        AutomationSchedulePreset(kind: .weekly, hour: 7, weekdays: {5, 1}),
        '0 7 * * 1,5',
      ),
      (
        AutomationSchedulePreset(kind: .everyHours, minute: 15, everyHours: 6),
        '15 */6 * * *',
      ),
    ];
    for (final (preset, cron) in cases) {
      expect(preset.cron, cron);
      final parsed = AutomationSchedulePreset.fromSchedule(<String, Object?>{
        'recurring': <String, Object?>{'cron': cron},
      });
      expect(parsed.kind, preset.kind);
      expect(parsed.cron, cron);
    }
  });

  test('unknown expressions stay custom cron', () {
    final parsed = AutomationSchedulePreset.fromSchedule(<String, Object?>{
      'recurring': <String, Object?>{'cron': '0 9 1 * *'},
    });
    expect(parsed.kind, AutomationScheduleKind.custom);
    expect(parsed.customCron, '0 9 1 * *');
  });

  test('one-time schedules send a UTC instant and describe locally', () {
    final at = DateTime(2026, 10, 6, 14, 5);
    final preset = AutomationSchedulePreset(kind: .once, onceAt: at);
    final schedule = preset.toSchedule(timezone: 'UTC');
    expect((schedule['oneTime']! as Map)['at'], at.toUtc().toIso8601String());
    expect(preset.describe(), startsWith('Once on Oct 6, 2026'));
  });

  test('local errors explain what is missing', () {
    expect(
      const AutomationSchedulePreset(kind: .weekly, weekdays: {}).localError,
      'Choose at least one day.',
    );
    expect(
      const AutomationSchedulePreset(
        kind: .custom,
        customCron: '0 9 *',
      ).localError,
      isNotNull,
    );
    expect(const AutomationSchedulePreset(kind: .once).localError, isNotNull);
    expect(AutomationSchedulePreset.initial.localError, isNull);
  });

  test('describes schedules in words with the time zone', () {
    expect(
      automationScheduleDescription(<String, Object?>{
        'recurring': <String, Object?>{
          'cron': '0 9 * * 1-5',
          'timezone': 'America/Havana',
        },
      }),
      'Weekdays at 09:00 · America/Havana',
    );
  });
}
