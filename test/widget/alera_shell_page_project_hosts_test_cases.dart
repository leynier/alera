part of 'alera_shell_page_test.dart';

void _registerProjectHostsMenuTests() {
  Future<void> openProjectMenu(WidgetTester tester) async {
    await tester.tapAt(
      tester.getCenter(find.text('Alera').last),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the project menu opens the Hosts dialog', (tester) async {
    final requests = <String>[];
    await _pumpShell(
      tester,
      state: _linkedWorkbenchState(),
      projectHostsSupported: true,
      projectHostsClient: RuntimeProjectHostsClient((
        type,
        payload,
        timeout,
      ) async {
        requests.add('$type ${payload['projectId']}');
        return <String, Object?>{
          'hosts': <Object?>[
            <String, Object?>{
              'hostId': 'local',
              'path': '/repo/alera',
              'primary': true,
              'workspaceCount': 2,
            },
          ],
        };
      }),
    );

    await openProjectMenu(tester);
    await tester.tap(find.text('Hosts'));
    await tester.pumpAndSettle();

    expect(requests, <String>['project.hosts.list project-1']);
    expect(find.text('Alera Hosts'), findsOneWidget);
    expect(find.text('This Device'), findsOneWidget);
    expect(find.text('2 workspaces'), findsOneWidget);
  });

  testWidgets('a runtime without project hosts hides the Hosts entry', (
    tester,
  ) async {
    await _pumpShell(tester, state: _linkedWorkbenchState());

    await openProjectMenu(tester);

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Hosts'), findsNothing);
  });

  testWidgets('a folder project has no Hosts entry', (tester) async {
    final state = _linkedWorkbenchState();
    await _pumpShell(
      tester,
      state: state.copyWith(
        projects: <Project>[
          state.projects.single.copyWith(kind: ProjectKind.folder),
        ],
      ),
      projectHostsSupported: true,
    );

    await openProjectMenu(tester);

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Hosts'), findsNothing);
  });
}
