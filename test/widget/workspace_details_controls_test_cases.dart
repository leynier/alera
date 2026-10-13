part of 'workspace_details_overlay_test.dart';

void _registerWorkspaceDetailsControlTests() {
  testWidgets('Changes keeps its label and counts while refreshing', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final refresh = Completer<WorkspaceDetailsState>();
    var loads = 0;
    await pumpOverlay(
      tester,
      const Size(1000, 700),
      loadDetails: () {
        return loads++ == 0 ? Future.value(details) : refresh.future;
      },
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkspaceDetailsOverlay)),
    );
    container.invalidate(workspaceDetailsProvider(scope));
    await tester.pump();
    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('Loading…'), findsNothing);
    expect(find.text('+42'), findsOneWidget);
    refresh.complete(details);
    await tester.pumpAndSettle();
    expect(find.text('Changes'), findsOneWidget);
  });

  testWidgets('workspace details toggle joins the movable terminal controls', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = _ToolbarSession();
    addTearDown(session.dispose);
    await pumpOverlay(
      tester,
      const Size(1000, 700),
      child: Stack(
        children: [
          TerminalSurfaceToolbar(
            session: session,
            viewportSize: const Size(1000, 700),
            corner: TerminalToolbarCorner.topRight,
            refreshing: false,
            onRefresh: () {},
          ),
        ],
      ),
    );
    final toggle = find.byTooltip('Toggle Workspace Details');
    expect(toggle, findsOneWidget);
    final toggleRect = tester.getRect(toggle);
    final refreshRect = tester.getRect(find.byTooltip('Refresh Terminal'));
    expect(toggleRect.top, refreshRect.top);
    expect(toggleRect.right, lessThan(refreshRect.left));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byType(AleraWorkspaceDetailsCard), findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byType(AleraWorkspaceDetailsCard), findsOneWidget);
    await tester.drag(find.byTooltip('Move Toolbar'), const Offset(-800, 500));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(toggle).top,
      tester.getRect(find.byTooltip('Refresh Terminal')).top,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow terminal popup works and falls back after the terminal closes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = _ToolbarSession();
      addTearDown(session.dispose);
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await pumpOverlay(
        tester,
        const Size(400, 400),
        child: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, show, _) => Stack(
            children: [
              if (show)
                TerminalSurfaceToolbar(
                  session: session,
                  viewportSize: const Size(400, 400),
                  corner: TerminalToolbarCorner.topRight,
                  refreshing: false,
                  onRefresh: () {},
                ),
            ],
          ),
        ),
      );
      expect(find.byType(AleraWorkspaceDetailsCard), findsNothing);
      expect(find.byTooltip('Toggle Workspace Details'), findsOneWidget);
      await tester.tap(find.byTooltip('Toggle Workspace Details'));
      await tester.pumpAndSettle();
      expect(find.text('Changes'), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(TerminalSurfaceToolbar), findsNothing);
      expect(find.byTooltip('Toggle Workspace Details'), findsOneWidget);
      await tester.tap(find.byTooltip('Toggle Workspace Details'));
      await tester.pumpAndSettle();
      expect(find.text('Changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ToolbarSession extends TerminalSessionHandle {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
