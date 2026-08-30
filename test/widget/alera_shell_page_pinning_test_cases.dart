part of 'alera_shell_page_test.dart';

class _PinningShellTestWorkbenchController(super.bootstrapState)
    extends _ShellTestWorkbenchController {
  final List<({String workspaceId, bool isPinned})> pinUpdates =
      <({String workspaceId, bool isPinned})>[];

  @override
  Future<void> setWorkspacePinned({
    required String workspaceId,
    required bool isPinned,
  }) async {
    pinUpdates.add((workspaceId: workspaceId, isPinned: isPinned));
    state = state.copyWith(
      workspacesByProject: <String, List<Workspace>>{
        for (final entry in state.workspacesByProject.entries)
          entry.key: <Workspace>[
            for (final workspace in entry.value)
              workspace.id == workspaceId
                  ? workspace.copyWith(isPinned: isPinned)
                  : workspace,
          ],
      },
    );
  }
}

void _registerAleraShellPinningTests() {
  testWidgets('pinned section duplicates the workspace and shows indicators', (
    tester,
  ) async {
    final seeded = _linkedWorkbenchState();
    final linked = seeded
        .workspacesFor('project-1')[1]
        .copyWith(isPinned: true);
    await _pumpShell(
      tester,
      state: seeded.copyWith(
        workspacesByProject: <String, List<Workspace>>{
          'project-1': <Workspace>[
            seeded.workspacesFor('project-1').first,
            linked,
          ],
        },
      ),
    );

    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Feature login'), findsNWidgets(2));
    expect(find.byKey(const Key('workspace-tray-pinned')), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('workspace-row:pinned:workspace-2')),
      findsOneWidget,
    );
  });

  testWidgets('workspace context menu pins and unpins without confirmation', (
    tester,
  ) async {
    final controller = _PinningShellTestWorkbenchController(
      _linkedWorkbenchState(),
    );
    await _pumpShell(
      tester,
      state: _linkedWorkbenchState(),
      controller: controller,
    );
    final regular = find.byKey(
      const ValueKey<String>('workspace-row:regular:workspace-2'),
    );

    await tester.tapAt(
      tester.getCenter(regular),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin Workspace'));
    await tester.pumpAndSettle();

    expect(controller.pinUpdates, <({String workspaceId, bool isPinned})>[
      (workspaceId: 'workspace-2', isPinned: true),
    ]);
    expect(find.text('Pinned'), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(regular),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpin Workspace'));
    await tester.pumpAndSettle();

    expect(controller.pinUpdates.last.isPinned, isFalse);
    expect(find.text('Pinned'), findsNothing);
  });

  testWidgets('view preference hides the regular pinned workspace copy', (
    tester,
  ) async {
    final seeded = _linkedWorkbenchState();
    final linked = seeded
        .workspacesFor('project-1')[1]
        .copyWith(isPinned: true);
    await _pumpShell(
      tester,
      state: seeded.copyWith(
        workspacesByProject: <String, List<Workspace>>{
          'project-1': <Workspace>[
            seeded.workspacesFor('project-1').first,
            linked,
          ],
        },
        viewPrefs: seeded.viewPrefs.copyWith(showPinnedWorkspacesBelow: false),
      ),
    );

    expect(find.text('Feature login'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('workspace-row:pinned:workspace-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('workspace-row:regular:workspace-2')),
      findsNothing,
    );
  });

  testWidgets('flat grouping shows collapsible pinned and all sections', (
    tester,
  ) async {
    final seeded = _linkedWorkbenchState();
    final linked = seeded
        .workspacesFor('project-1')[1]
        .copyWith(isPinned: true);
    final harness = await _pumpShell(
      tester,
      state: seeded.copyWith(
        workspacesByProject: <String, List<Workspace>>{
          'project-1': <Workspace>[
            seeded.workspacesFor('project-1').first,
            linked,
          ],
        },
        viewPrefs: seeded.viewPrefs.copyWith(groupBy: .none),
      ),
    );

    final pinnedCopy = find.byKey(
      const ValueKey<String>('workspace-row:pinned:workspace-2'),
    );
    final regularRow = find.byKey(
      const ValueKey<String>('workspace-row:regular:workspace-2'),
    );
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(pinnedCopy, findsOneWidget);
    expect(regularRow, findsOneWidget);

    await tester.tap(find.text('Pinned'));
    await tester.pumpAndSettle();
    expect(harness.controller.state.viewPrefs.pinnedSectionCollapsed, isTrue);
    expect(pinnedCopy, findsNothing);
    expect(regularRow, findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(harness.controller.state.viewPrefs.allSectionCollapsed, isTrue);
    expect(regularRow, findsNothing);

    await tester.tap(find.text('Pinned'));
    await tester.pumpAndSettle();
    expect(harness.controller.state.viewPrefs.pinnedSectionCollapsed, isFalse);
    expect(pinnedCopy, findsOneWidget);
  });
}
