import 'package:alera/src/features/workbench/domain/terminal_refresh_resize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('terminalPtyRefreshPulseSize', () {
    test('shrinks both axes by about 30%', () {
      expect(terminalPtyRefreshPulseSize(120, 40), (84, 28));
      expect(terminalPtyRefreshPulseSize(80, 24), (56, 17));
      expect(terminalPtyRefreshPulseSize(10, 10), (7, 7));
    });

    test('changes a one-cell viewport and leaves invalid sizes alone', () {
      expect(terminalPtyRefreshPulseSize(1, 1), (2, 2));
      expect(terminalPtyRefreshPulseSize(2, 2), (1, 1));
      expect(terminalPtyRefreshPulseSize(0, 24), (0, 24));
      expect(terminalPtyRefreshPulseSize(80, 0), (80, 0));
    });
  });

  group('terminalEmulatorFakeResizeSize', () {
    test('bumps both axes by about 30%', () {
      expect(terminalEmulatorFakeResizeSize(80, 24), (104, 31));
      expect(terminalEmulatorFakeResizeSize(120, 40), (156, 52));
      expect(terminalEmulatorFakeResizeSize(10, 10), (13, 13));
    });

    test('always changes a positive size by at least one cell', () {
      expect(terminalEmulatorFakeResizeSize(1, 1), (2, 2));
      expect(terminalEmulatorFakeResizeSize(2, 3), (3, 4));
    });

    test('leaves non-positive sizes alone so a bad viewport is not sent', () {
      expect(terminalEmulatorFakeResizeSize(0, 24), (0, 24));
      expect(terminalEmulatorFakeResizeSize(80, 0), (80, 0));
      expect(terminalEmulatorFakeResizeSize(-1, 10), (-1, 10));
    });
  });

  group('pulseTerminalEmulatorSize', () {
    test('resizes to the bump then restores the original size in order', () {
      final sizes = <(int, int)>[];

      pulseTerminalEmulatorSize(
        cols: 80,
        rows: 24,
        resize: (cols, rows) => sizes.add((cols, rows)),
      );

      expect(sizes, <(int, int)>[(104, 31), (80, 24)]);
    });

    test('does not resize when the viewport cannot change', () {
      final sizes = <(int, int)>[];

      pulseTerminalEmulatorSize(
        cols: 0,
        rows: 24,
        resize: (cols, rows) => sizes.add((cols, rows)),
      );
      pulseTerminalEmulatorSize(
        cols: 80,
        rows: 0,
        resize: (cols, rows) => sizes.add((cols, rows)),
      );

      expect(sizes, isEmpty);
    });
  });
}
