part of 'workspace_details_overlay_test.dart';

void _registerWorkspaceDetailsControlTests() {
  testWidgets('the card sits right under a top right terminal toolbar', (
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
    expect(
      tester.getRect(find.byType(AleraWorkspaceDetailsCard)).top,
      tester.getRect(find.byTooltip('Refresh Terminal')).bottom +
          AleraTokens.space8,
    );
  });

  test('the card top follows the tab strip and toolbar corner', () {
    final single = workspaceDetailsCardTop(
      tabStrip: false,
      toolbarCorner: TerminalToolbarCorner.topRight,
    );
    expect(
      workspaceDetailsCardTop(
        tabStrip: true,
        toolbarCorner: TerminalToolbarCorner.topRight,
      ),
      single + AleraTokens.sidebarHeaderHeight,
    );
    for (final corner in TerminalToolbarCorner.values) {
      if (corner == TerminalToolbarCorner.topRight) continue;
      expect(
        workspaceDetailsCardTop(tabStrip: false, toolbarCorner: corner),
        AleraTokens.space8,
      );
      // The card never covers the tab strip's new-tab and split controls.
      expect(
        workspaceDetailsCardTop(tabStrip: true, toolbarCorner: corner),
        AleraTokens.sidebarHeaderHeight + AleraTokens.space8,
      );
    }
    expect(
      workspaceDetailsCardTop(tabStrip: false, toolbarCorner: null),
      greaterThan(single),
    );
  });

  testWidgets('row menus open under their row in a grouped order', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(tester, const Size(1000, 1000));
    final row = find.byTooltip('Commit & Push Options');
    final rowBottom = tester.getRect(row).bottom;
    await tester.tap(row);
    await tester.pumpAndSettle();
    double top(String label) => tester.getRect(find.text(label).last).top;
    expect(top('Commit'), greaterThan(rowBottom));
    expect(top('Push'), lessThan(top('Push & Create PR')));
    expect(top('Push & Create PR'), lessThan(top('Pull')));
    expect(top('Pull'), lessThan(top('Refresh')));
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Pull').last,
          matching: find.byType(Row),
        ),
        matching: find.byIcon(AleraIcons.gitPull),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final open = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          (widget.message?.startsWith('Open In') ?? false) &&
          (widget.message?.endsWith('Options') ?? false),
    );
    final openBottom = tester.getRect(open).bottom;
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(top('Copy Path'), greaterThan(openBottom));
    expect(top('Open In Browser'), lessThan(top('Copy Path')));
  });

  testWidgets('Changes opens Source Control in the side panel', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(tester, const Size(1000, 700));
    // The counts describe the uncommitted files Source Control lists, not the
    // base comparison.
    expect(find.text('+42'), findsOneWidget);
    expect(find.text('-8'), findsOneWidget);
    expect(find.text('+100'), findsNothing);
    await tester.tap(find.text('Changes'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkspaceDetailsOverlay)),
    );
    final prefs = container.read(workbenchControllerProvider).viewPrefs;
    expect(prefs.activeContextPanelTab, WorkbenchContextPanelTab.gitDiff);
    expect(prefs.rightSidebarVisible, isTrue);
    expect(find.text('Compare against origin/main'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

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
      final popup = find.byType(AleraWorkspaceDetailsCard);
      final popupRect = tester.getRect(popup);
      final toggleRect = tester.getRect(
        find.byTooltip('Toggle Workspace Details'),
      );
      expect(popupRect.top, toggleRect.bottom + AleraTokens.space8);
      expect(tester.binding.hasScheduledFrame, isFalse);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WorkspaceDetailsOverlay)),
      );
      container
          .read(workbenchControllerProvider.notifier)
          .toggleWorkspaceDetails(workspace.id);
      await tester.pumpAndSettle();
      expect(tester.getRect(popup), popupRect);
      expect(tester.binding.hasScheduledFrame, isFalse);
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
  void requestFocus() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
