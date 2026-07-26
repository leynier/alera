import 'package:alera/src/features/resource_manager/domain/machine_cpu_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('machineCpuShare', () {
    test('a fully saturated machine reads 100%', () {
      // `sysinfo` caps a row at `cores * 100`, which is every core busy.
      expect(machineCpuShare(1600, 16), 100);
    });

    test('a process busier than one core stays below the machine total', () {
      // The reading from the report that prompted this: 113.5% of one core on a
      // 16-core machine is 7.1% of the machine, not more than all of it.
      expect(machineCpuShare(113.6, 16), closeTo(7.1, 0.01));
    });

    test('a single-core machine passes the reading through', () {
      expect(machineCpuShare(42, 1), 42);
    });

    test('an absent reading stays absent', () {
      expect(machineCpuShare(null, 8), isNull);
    });

    test('an unknown core count yields no share', () {
      // Dividing by zero would read `Infinity`, and passing the per-core value
      // through would silently claim it is already a machine share.
      expect(machineCpuShare(320, 0), isNull);
      expect(machineCpuShare(320, -1), isNull);
    });
  });
}
