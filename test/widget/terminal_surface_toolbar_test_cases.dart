part of 'terminal_surface_test.dart';

void _registerTerminalSurfaceToolbarTests() {
  testWidgets('toolbar cluster sits in the persisted corner', (tester) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');

    await _pumpTerminalSurface(
      tester,
      session,
      settings: AleraSettings.defaults.copyWith(
        terminal: TerminalSettings.defaults.copyWith(
          toolbarCorner: .bottomLeft,
        ),
      ),
    );

    final surfaceRect = tester.getRect(find.byType(TerminalSurface));
    final composerRect = tester.getRect(
      find.byTooltip('Show Terminal Composer'),
    );
    final refreshRect = tester.getRect(find.byTooltip('Refresh Terminal'));
    final moveRect = tester.getRect(find.byTooltip('Move Toolbar'));

    expect(
      composerRect.left,
      closeTo(surfaceRect.left + AleraTokens.space4, 0.01),
    );
    expect(
      composerRect.bottom,
      closeTo(surfaceRect.bottom - AleraTokens.space4, 0.01),
    );
    expect(composerRect.right, lessThan(refreshRect.left));
    expect(refreshRect.right, lessThan(moveRect.left));
    expect(moveRect.bottom, composerRect.bottom);
  });

  testWidgets('right-clicking the cluster moves it to another corner', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');

    await _pumpTerminalSurface(tester, session);

    await tester.tap(find.byTooltip('Move Toolbar'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top Left'));
    await tester.pumpAndSettle();

    final surfaceRect = tester.getRect(find.byType(TerminalSurface));
    final composerRect = tester.getRect(
      find.byTooltip('Show Terminal Composer'),
    );
    expect(
      composerRect.left,
      closeTo(surfaceRect.left + AleraTokens.space4, 0.01),
    );
    expect(
      composerRect.top,
      closeTo(surfaceRect.top + AleraTokens.space4, 0.01),
    );
  });

  testWidgets('dragging the cluster snaps it to the nearest corner', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');

    await _pumpTerminalSurface(tester, session);

    final surfaceRect = tester.getRect(find.byType(TerminalSurface));
    await tester.drag(
      find.byTooltip('Move Toolbar'),
      Offset(-surfaceRect.width * 0.7, surfaceRect.height * 0.7),
    );
    await tester.pumpAndSettle();

    final composerRect = tester.getRect(
      find.byTooltip('Show Terminal Composer'),
    );
    expect(
      composerRect.left,
      closeTo(surfaceRect.left + AleraTokens.space4, 0.01),
    );
    expect(
      composerRect.bottom,
      closeTo(surfaceRect.bottom - AleraTokens.space4, 0.01),
    );
  });
}
