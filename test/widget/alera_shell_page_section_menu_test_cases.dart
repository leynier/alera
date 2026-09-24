part of 'alera_shell_page_test.dart';

class _SectionMenuShellTestWorkbenchController(super.bootstrapState)
    extends _ShellTestWorkbenchController {
  final List<
    ({String workspaceId, String? sectionId, String? newName, bool tree})
  >
  saves =
      <({String workspaceId, String? sectionId, String? newName, bool tree})>[];

  @override
  Future<void> saveWorkspaceSection(
    String workspaceId, {
    String? sectionId,
    String? newName,
  }) async {
    saves.add((
      workspaceId: workspaceId,
      sectionId: sectionId,
      newName: newName,
      tree: false,
    ));
  }

  @override
  Future<void> saveWorkspaceSectionTree(
    String workspaceId, {
    String? sectionId,
    String? newName,
  }) async {
    saves.add((
      workspaceId: workspaceId,
      sectionId: sectionId,
      newName: newName,
      tree: true,
    ));
  }
}

WorkspaceSection _menuSection(String id, String name) {
  final now = DateTime.utc(2026, 8, 30);
  return WorkspaceSection(id: id, name: name, createdAt: now, updatedAt: now);
}

void _registerAleraShellSectionMenuTests() {
  testWidgets('workspace tree offers section tree actions', (tester) async {
    final seeded = _linkedWorkbenchState();
    final workspaces = seeded.workspacesFor('project-1');
    final parent = workspaces.first.copyWith(sectionId: 'work');
    final child = workspaces.last.copyWith(parentWorkspaceId: parent.id);
    final state = seeded.copyWith(
      supportsSections: true,
      sections: <WorkspaceSection>[_menuSection('work', 'Work')],
      workspacesByProject: <String, List<Workspace>>{
        'project-1': <Workspace>[parent, child],
      },
    );
    await _pumpShell(tester, state: state);
    await tester.tapAt(
      tester.getCenter(
        find.byKey(ValueKey<String>('workspace-row:regular:${parent.id}')),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Section'), findsOneWidget);
    await tester.tap(find.text('Section'));
    await tester.pumpAndSettle();
    expect(find.text('Clear Section'), findsOneWidget);
    expect(find.text('Apply to Tree'), findsOneWidget);
    await tester.tap(find.text('Apply to Tree'));
    await tester.pumpAndSettle();
    expect(find.text('Clear Section Tree'), findsOneWidget);
  });

  testWidgets('Set Section submenu assigns an existing section', (
    tester,
  ) async {
    final state = _linkedWorkbenchState().copyWith(
      supportsSections: true,
      sections: <WorkspaceSection>[_menuSection('work', 'Work')],
    );
    final controller = _SectionMenuShellTestWorkbenchController(state);
    await _pumpShell(tester, state: state, controller: controller);
    await tester.tapAt(
      tester.getCenter(
        find.byKey(const ValueKey<String>('workspace-row:regular:workspace-2')),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Section'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('New Section'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    expect(
      controller.saves,
      <({String workspaceId, String? sectionId, String? newName, bool tree})>[
        (
          workspaceId: 'workspace-2',
          sectionId: 'work',
          newName: null,
          tree: false,
        ),
      ],
    );
  });

  testWidgets('Set Section Tree submenu assigns the whole tree', (
    tester,
  ) async {
    final seeded = _linkedWorkbenchState();
    final workspaces = seeded.workspacesFor('project-1');
    final parent = workspaces.first;
    final child = workspaces.last.copyWith(parentWorkspaceId: parent.id);
    final state = seeded.copyWith(
      supportsSections: true,
      sections: <WorkspaceSection>[_menuSection('work', 'Work')],
      workspacesByProject: <String, List<Workspace>>{
        'project-1': <Workspace>[parent, child],
      },
    );
    final controller = _SectionMenuShellTestWorkbenchController(state);
    await _pumpShell(tester, state: state, controller: controller);
    await tester.tapAt(
      tester.getCenter(
        find.byKey(ValueKey<String>('workspace-row:regular:${parent.id}')),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Section'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply to Tree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();

    expect(controller.saves.single.tree, isTrue);
    expect(controller.saves.single.sectionId, 'work');
    expect(controller.saves.single.workspaceId, parent.id);
  });
}
