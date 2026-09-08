import 'package:alera_mobile/src/features/terminal/domain/terminal_viewport_pulse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('layout pulse stays one column so keyboard and rotation stay cheap', () {
    expect(terminalViewportPulseSize(120, 40), (119, 40));
    expect(terminalViewportPulseSize(1, 1), (2, 1));
    expect(terminalViewportPulseSize(80, 24), (79, 24));
  });

  test('Refresh pulse shrinks both axes by about 30 percent', () {
    expect(terminalViewportRefreshPulseSize(120, 40), (84, 28));
    expect(terminalViewportRefreshPulseSize(80, 24), (56, 17));
    expect(terminalViewportRefreshPulseSize(10, 10), (7, 7));
  });

  test('Refresh pulse still moves a 1-cell edge instead of staying put', () {
    expect(terminalViewportRefreshPulseSize(1, 1), (2, 2));
    expect(terminalViewportRefreshPulseSize(2, 2), (1, 1));
  });

  test('Refresh pulse is wider than the layout pulse on a normal viewport', () {
    expect(
      terminalViewportRefreshPulseSize(80, 24),
      isNot(terminalViewportPulseSize(80, 24)),
    );
  });

  test('leaves non-positive sizes alone so a bad viewport is not sent', () {
    expect(terminalViewportPulseSize(0, 24), (0, 24));
    expect(terminalViewportPulseSize(80, 0), (80, 0));
    expect(terminalViewportPulseSize(-1, 10), (-1, 10));
    expect(terminalViewportRefreshPulseSize(0, 24), (0, 24));
    expect(terminalViewportRefreshPulseSize(80, 0), (80, 0));
    expect(terminalViewportRefreshPulseSize(-1, 10), (-1, 10));
  });
}
