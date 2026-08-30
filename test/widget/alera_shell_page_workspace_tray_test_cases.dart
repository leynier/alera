part of 'alera_shell_page_test.dart';

void _registerAleraShellWorkspaceTrayTests() {
  testWidgets('workspace rows show tags and children in the icon tray', (
    tester,
  ) async {
    final seeded = _linkedWorkbenchState(linkedExpanded: true);
    final workspaces = seeded.workspacesFor('project-1');
    final parent = workspaces.first.copyWith(childCount: 1);
    final child = workspaces.last.copyWith(
      parentWorkspaceId: parent.id,
      tagNames: const <String>['frontend', 'review', 'qa', 'ux'],
    );

    await _pumpShell(
      tester,
      state: seeded.copyWith(
        workspacesByProject: <String, List<Workspace>>{
          'project-1': <Workspace>[parent, child],
        },
      ),
    );

    expect(find.text('#frontend'), findsNothing);
    expect(find.byKey(const Key('workspace-tray-tags')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && widget.message == 'frontend, review, qa, ux',
      ),
      findsOneWidget,
    );
    expect(find.text('Child'), findsNothing);
    expect(find.text('1 Child'), findsNothing);
    expect(find.text('1 child'), findsNothing);
    expect(find.byTooltip('Remove Workspace'), findsNothing);
    expect(find.byKey(const Key('workspace-tray-children')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('workspace-tray-children')),
        matching: find.byIcon(AleraIcons.workspaceChildren),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Hide Child Workspaces'), findsOneWidget);
  });
}
