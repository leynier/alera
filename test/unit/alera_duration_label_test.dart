import 'package:alera/src/design_system/forms/alera_duration_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('labels a duration in the largest unit that divides it', () {
    expect(aleraDurationLabel(90), '90 seconds');
    expect(aleraDurationLabel(1), '1 second');
    expect(aleraDurationLabel(0), '0 seconds');
    expect(aleraDurationLabel(60), '1 minute');
    expect(aleraDurationLabel(900), '15 minutes');
    expect(aleraDurationLabel(7200), '2 hours');
    expect(aleraDurationLabel(86400), '1 day');
    expect(aleraDurationLabel(172800), '2 days');
  });

  test('display unit falls back to the smallest offered unit', () {
    const units = <AleraDurationUnit>[
      AleraDurationUnit.minutes,
      AleraDurationUnit.hours,
    ];
    expect(aleraDurationDisplayUnit(7200, units), AleraDurationUnit.hours);
    expect(aleraDurationDisplayUnit(90, units), AleraDurationUnit.minutes);
    expect(aleraDurationDisplayUnit(0, units), AleraDurationUnit.minutes);
  });
}
