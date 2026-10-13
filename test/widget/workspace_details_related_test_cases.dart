part of 'workspace_details_overlay_test.dart';

Workspace _related(String id, String name, {String? parent}) => Workspace(
  id: id,
  projectId: 'p',
  name: name,
  path: '/repo-$id',
  branch: 'feature/$id',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  kind: WorkspaceKind.linked,
  status: WorkspaceStatus.active,
  parentWorkspaceId: parent,
);

WorkbenchState _relatedState(List<Workspace> others, {String? parent}) =>
    WorkbenchState(
      activeWorkspaceId: 'w',
      projects: [
        Project(
          id: 'p',
          name: 'Alera',
          repoPath: '/repo',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ],
      workspacesByProject: {
        'p': [_related('w', 'Details', parent: parent), ...others],
      },
    );

_Workbench _workbenchOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(WorkspaceDetailsOverlay)),
).read(workbenchControllerProvider.notifier) as _Workbench;

void _registerWorkspaceDetailsRelatedTests() {
  testWidgets('a child workspace opens its parent from the card', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(
      tester,
      const Size(1000, 800),
      workbench: _relatedState([
        _related('root', 'Root'),
        _related('kid', 'Kid', parent: 'w'),
      ], parent: 'root'),
    );
    expect(find.text('Child of Root'), findsOneWidget);
    expect(find.text('1 Child Workspace'), findsOneWidget);
    await tester.tap(find.text('Child of Root'));
    await tester.pumpAndSettle();
    expect(_workbenchOf(tester).selectedWorkspaces, ['root']);
    await tester.tap(find.byTooltip('Child of Root Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kid'));
    await tester.pumpAndSettle();
    expect(_workbenchOf(tester).selectedWorkspaces, ['root', 'kid']);
  });

  testWidgets('a parent lists its active children and skips archived ones', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final archived = Workspace(
      id: 'old',
      projectId: 'p',
      name: 'Old',
      path: '/repo-old',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      kind: WorkspaceKind.linked,
      status: WorkspaceStatus.active,
      parentWorkspaceId: 'w',
      isArchived: true,
    );
    await pumpOverlay(
      tester,
      const Size(1000, 800),
      workbench: _relatedState([
        _related('b', 'Beta', parent: 'w'),
        _related('a', 'Alpha', parent: 'w'),
        archived,
      ]),
    );
    expect(find.text('2 Child Workspaces'), findsOneWidget);
    await tester.tap(find.text('2 Child Workspaces'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Beta')).dy),
    );
    expect(find.text('Old'), findsNothing);
  });

  testWidgets('an unrelated workspace has no related row', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(
      tester,
      const Size(1000, 800),
      workbench: _relatedState([_related('x', 'Other')]),
    );
    expect(find.byIcon(AleraIcons.workspaceChildren), findsNothing);
  });
}
