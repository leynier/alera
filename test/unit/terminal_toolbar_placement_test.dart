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
    final bottomRight = terminalSearchOverlayLayout(
      toolbarCorner: TerminalToolbarCorner.bottomRight,
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
    expect(bottomRight.left, AleraTokens.space16);
    expect(bottomRight.alignLeft, isFalse);
  });

  test('counts the move handle with the other toolbar actions', () {
    expect(
      terminalToolbarButtonCount(supportsPulse: false, hasCanvas: false),
      3,
    );
    expect(
      terminalToolbarButtonCount(supportsPulse: true, hasCanvas: false),
      4,
    );
    expect(
      terminalToolbarButtonCount(supportsPulse: false, hasCanvas: true),
      4,
    );
    expect(terminalToolbarButtonCount(supportsPulse: true, hasCanvas: true), 5);
  });

  test('places a dragged cluster at the matching corner offset', () {
    const inset = AleraTokens.space4;
    const viewportWidth = 400.0;
    const viewportHeight = 300.0;
    const toolbarWidth = 120.0;
    const toolbarHeight = 28.0;

    expect(
      terminalToolbarOffset(
        corner: TerminalToolbarCorner.topLeft,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        toolbarWidth: toolbarWidth,
        toolbarHeight: toolbarHeight,
      ),
      (left: inset, top: inset),
    );
    expect(
      terminalToolbarOffset(
        corner: TerminalToolbarCorner.topRight,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        toolbarWidth: toolbarWidth,
        toolbarHeight: toolbarHeight,
      ),
      (left: viewportWidth - toolbarWidth - inset, top: inset),
    );
    expect(
      terminalToolbarOffset(
        corner: TerminalToolbarCorner.bottomLeft,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        toolbarWidth: toolbarWidth,
        toolbarHeight: toolbarHeight,
      ),
      (left: inset, top: viewportHeight - toolbarHeight - inset),
    );
    expect(
      terminalToolbarOffset(
        corner: TerminalToolbarCorner.bottomRight,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        toolbarWidth: toolbarWidth,
        toolbarHeight: toolbarHeight,
      ),
      (
        left: viewportWidth - toolbarWidth - inset,
        top: viewportHeight - toolbarHeight - inset,
      ),
    );
  });

  test('clamps a dragged cluster inside the viewport', () {
    const inset = AleraTokens.space4;
    const viewportWidth = 400.0;
    const viewportHeight = 300.0;
    const toolbarWidth = 120.0;
    const toolbarHeight = 28.0;
    final maxLeft = viewportWidth - toolbarWidth - inset;
    final maxTop = viewportHeight - toolbarHeight - inset;

    expect(
      clampTerminalToolbarLeft(
        left: -40,
        viewportWidth: viewportWidth,
        toolbarWidth: toolbarWidth,
      ),
      inset,
    );
    expect(
      clampTerminalToolbarLeft(
        left: 80,
        viewportWidth: viewportWidth,
        toolbarWidth: toolbarWidth,
      ),
      80,
    );
    expect(
      clampTerminalToolbarLeft(
        left: 500,
        viewportWidth: viewportWidth,
        toolbarWidth: toolbarWidth,
      ),
      maxLeft,
    );
    expect(
      clampTerminalToolbarTop(
        top: -40,
        viewportHeight: viewportHeight,
        toolbarHeight: toolbarHeight,
      ),
      inset,
    );
    expect(
      clampTerminalToolbarTop(
        top: 90,
        viewportHeight: viewportHeight,
        toolbarHeight: toolbarHeight,
      ),
      90,
    );
    expect(
      clampTerminalToolbarTop(
        top: 500,
        viewportHeight: viewportHeight,
        toolbarHeight: toolbarHeight,
      ),
      maxTop,
    );
  });

  test(
    'pins a dragged cluster when the viewport is smaller than the toolbar',
    () {
      const inset = AleraTokens.space4;

      expect(
        clampTerminalToolbarLeft(
          left: 80,
          viewportWidth: 40,
          toolbarWidth: 120,
        ),
        inset,
      );
      expect(
        clampTerminalToolbarTop(top: 80, viewportHeight: 20, toolbarHeight: 28),
        inset,
      );
    },
  );

  test('treats equal toolbar anchors as interchangeable', () {
    const left = TerminalToolbarAnchor(top: 8, left: 8);
    const same = TerminalToolbarAnchor(top: 8, left: 8);
    const other = TerminalToolbarAnchor(top: 8, right: 8);

    expect(left, same);
    expect(left.hashCode, same.hashCode);
    expect(left, isNot(other));
    expect(left, isNot(Object()));
  });
}
