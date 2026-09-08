import 'package:alera_mobile/src/features/terminal/domain/terminal_viewport_pulse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pulses one column then restores, matching desktop refreshViewport', () {
    expect(terminalViewportPulseSize(120, 40), (119, 40));
    expect(terminalViewportPulseSize(1, 1), (2, 1));
    expect(terminalViewportPulseSize(80, 24), (79, 24));
  });

  test('leaves non-positive sizes alone so a bad viewport is not sent', () {
    expect(terminalViewportPulseSize(0, 24), (0, 24));
    expect(terminalViewportPulseSize(80, 0), (80, 0));
    expect(terminalViewportPulseSize(-1, 10), (-1, 10));
  });
}
