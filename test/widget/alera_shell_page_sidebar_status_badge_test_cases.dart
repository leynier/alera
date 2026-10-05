part of 'alera_shell_page_test.dart';

/// [_stackedWorkbenchState] narrowed to the minimum sidebar width, with a
/// workspace name long enough to need truncation.
WorkbenchState _narrowSidebarState() {
  final state = _stackedWorkbenchState();
  return state.copyWith(
    workspacesByProject: <String, List<Workspace>>{
      for (final entry in state.workspacesByProject.entries)
        entry.key: <Workspace>[
          for (final workspace in entry.value)
            workspace.copyWith(name: 'Payments reconciliation rework'),
        ],
    },
    viewPrefs: state.viewPrefs.copyWith(
      sidebarWidth: AleraTokens.sidebarMinWidth,
    ),
  );
}

/// Pumps [_narrowSidebarState] and returns the overflow reports raised by
/// anything other than the sidebar toolbar and footer. Those two overflow at
/// the minimum width under the test font, which draws every glyph as a
/// square, and are not what these cases cover.
Future<List<String>> _pumpNarrowSidebar(
  WidgetTester tester,
  AgentStatusState state,
) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final report = details.toDiagnosticsNode().toStringDeep();
    if (!report.contains('overflowed')) {
      previous?.call(details);
      return;
    }
    if (!report.contains('WorkbenchSidebarToolbar') &&
        !report.contains('_SidebarFooter')) {
      overflows.add(report);
    }
  };
  try {
    await _pumpShell(
      tester,
      state: _narrowSidebarState(),
      agentStatuses: <String, AgentStatusEntry>{
        'tab-1': _agentStatusEntry(
          terminalSessionId: 'tab-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
          state: state,
        ),
      },
    );
  } finally {
    FlutterError.onError = previous;
  }
  return overflows;
}

void _registerAleraShellSidebarStatusBadgeTests() {
  testWidgets(
    'a waiting workspace row shows Needs Input at the minimum sidebar width',
    (tester) async {
      final overflows = await _pumpNarrowSidebar(tester, .waiting);

      final row = find.byKey(
        const ValueKey<String>('workspace-row:regular:workspace-1'),
      );
      final badge = find.byKey(const Key('workspace-status-badge'));
      final name = find.byKey(const Key('workspace-row-name'));
      expect(overflows, isEmpty);
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('Needs Input')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip && widget.message == 'Waiting for input',
        ),
        findsWidgets,
      );
      // The badge outranks the inline trays at this width, so the name keeps
      // the room they would take.
      expect(find.byKey(const Key('workspace-tray-branch')), findsNothing);

      final rowRect = tester.getRect(row);
      final nameRect = tester.getRect(name);
      final badgeRect = tester.getRect(badge);
      expect(nameRect.width, greaterThanOrEqualTo(AleraTokens.space48));
      expect(nameRect.right, lessThanOrEqualTo(badgeRect.left));
      expect(badgeRect.right, lessThanOrEqualTo(rowRect.right));
    },
  );

  testWidgets('a working workspace row keeps its spinner without a badge', (
    tester,
  ) async {
    final overflows = await _pumpNarrowSidebar(tester, .working);

    expect(overflows, isEmpty);
    expect(find.byKey(const Key('workspace-status-badge')), findsNothing);
    expect(find.byKey(const Key('workspace-tray-branch')), findsOneWidget);
  });

  testWidgets('agent child rows label blocked and finished runs', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      state: _stackedWorkbenchState(),
      agentStatuses: <String, AgentStatusEntry>{
        'tab-1': _agentStatusEntry(
          terminalSessionId: 'tab-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
          state: .blocked,
        ),
        'tab-2': _agentStatusEntry(
          terminalSessionId: 'tab-2',
          workspaceId: 'workspace-1',
          tabId: 'tab-2',
          state: .done,
        ),
      },
    );

    await tester.tap(find.byTooltip('Show Agent Runs'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    // Two agents in the center nest as child rows, so the workspace row has
    // no primary status and therefore no badge of its own.
    expect(find.byKey(const Key('workspace-status-badge')), findsNothing);
  });
}
