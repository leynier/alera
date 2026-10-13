import 'package:alera/src/design_system/forms/alera_time_of_day_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses hours, minutes and meridiem suffixes', () {
    expect(parseAleraTimeOfDay('9'), (hour: 9, minute: 0));
    expect(parseAleraTimeOfDay('9:30'), (hour: 9, minute: 30));
    expect(parseAleraTimeOfDay('18:05'), (hour: 18, minute: 5));
    expect(parseAleraTimeOfDay('930'), (hour: 9, minute: 30));
    expect(parseAleraTimeOfDay('9:30 pm'), (hour: 21, minute: 30));
    expect(parseAleraTimeOfDay('9:30 P.M.'), (hour: 21, minute: 30));
    expect(parseAleraTimeOfDay('12am'), (hour: 0, minute: 0));
    expect(parseAleraTimeOfDay('12pm'), (hour: 12, minute: 0));
    expect(parseAleraTimeOfDay(' 0:00 '), (hour: 0, minute: 0));
  });

  test('rejects text that is not a time of day', () {
    for (final input in <String>[
      '',
      'noon',
      '24:00',
      '9:60',
      '9:5',
      '13pm',
      '0am',
      '9:30:15',
    ]) {
      expect(parseAleraTimeOfDay(input), isNull, reason: input);
    }
  });

  test('formats with two-digit hours and minutes', () {
    expect(formatAleraTimeOfDay(9, 5), '09:05');
    expect(formatAleraTimeOfDay(18, 30), '18:30');
  });
}
