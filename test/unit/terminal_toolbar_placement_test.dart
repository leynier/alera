import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/terminal_toolbar_placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('anchors the cluster to each terminal corner', () {
    const inset = AleraTokens.space4;

    expect(
      TerminalToolbarAnchor.forCorner(TerminalToolbarCorner.topRight),
      const TerminalToolbarAnchor(top: inset, right: inset),
    );
    expect(
      TerminalToolbarAnchor.forCorner(TerminalToolbarCorner.topLeft),
      const TerminalToolbarAnchor(top: inset, left: inset),
    );
    expect(
      TerminalToolbarAnchor.forCorner(TerminalToolbarCorner.bottomLeft),
      const TerminalToolbarAnchor(bottom: inset, left: inset),
    );
    expect(
      TerminalToolbarAnchor.forCorner(TerminalToolbarCorner.bottomRight),
      const TerminalToolbarAnchor(bottom: inset, right: inset),
    );
  });

  test('snaps the cluster center to the nearest corner', () {
    expect(
      nearestTerminalToolbarCorner(
        centerX: 10,
        centerY: 10,
        viewportWidth: 100,
        viewportHeight: 100,
      ),
      TerminalToolbarCorner.topLeft,
    );
    expect(
      nearestTerminalToolbarCorner(
        centerX: 90,
        centerY: 10,
        viewportWidth: 100,
        viewportHeight: 100,
      ),
      TerminalToolbarCorner.topRight,
    );
    expect(
      nearestTerminalToolbarCorner(
        centerX: 10,
        centerY: 90,
        viewportWidth: 100,
        viewportHeight: 100,
      ),
      TerminalToolbarCorner.bottomLeft,
    );
    expect(
      nearestTerminalToolbarCorner(
        centerX: 90,
        centerY: 90,
        viewportWidth: 100,
        viewportHeight: 100,
      ),
      TerminalToolbarCorner.bottomRight,
    );
  });

  test('keeps search clear of a top-side toolbar', () {
    const buttonCount = 3;
    final topRight = terminalSearchOverlayLayout(
      toolbarCorner: TerminalToolbarCorner.topRight,
      toolbarButtonCount: buttonCount,
    );
    final topLeft = terminalSearchOverlayLayout(
      toolbarCorner: TerminalToolbarCorner.topLeft,
      toolbarButtonCount: buttonCount,
    );
    final bottomLeft = terminalSearchOverlayLayout(
      toolbarCorner: TerminalToolbarCorner.bottomLeft,
      toolbarButtonCount: buttonCount,
    );

    expect(
      topRight.right,
      AleraTokens.space48 * buttonCount + AleraTokens.space4,
    );
    expect(topRight.alignLeft, isFalse);
    expect(
      topLeft.left,
      AleraTokens.space48 * buttonCount + AleraTokens.space4,
    );
    expect(topLeft.alignLeft, isTrue);
    expect(bottomLeft.left, AleraTokens.space16);
    expect(bottomLeft.right, AleraTokens.space16);
  });

  test('counts the move handle with the other toolbar actions', () {
    expect(
      terminalToolbarButtonCount(supportsPulse: false, hasCanvas: false),
      3,
    );
    expect(terminalToolbarButtonCount(supportsPulse: true, hasCanvas: true), 5);
  });
}
