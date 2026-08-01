part of 'settings_dialog_test.dart';

void _registerSettingsDialogProjectTests() {
  testWidgets('opens project settings with the requested project selected', (
    tester,
  ) async {
    final projects = <Project>[
      Project(
        id: 'project-1',
        name: 'First Project',
        repoPath: '/repo/first',
        createdAt: DateTime.utc(2026, 6, 27),
        updatedAt: DateTime.utc(2026, 6, 27),
      ),
      Project(
        id: 'project-2',
        name: 'Second Project',
        repoPath: '/repo/second',
        createdAt: DateTime.utc(2026, 6, 27),
        updatedAt: DateTime.utc(2026, 6, 27),
      ),
    ];
    final configRepository = FakeProjectConfigRepository();
    addTearDown(configRepository.dispose);
    final configService = ProjectConfigService(
      repository: configRepository,
      fileStore: FakeProjectConfigFileStore(),
      now: () => DateTime.utc(2026, 6, 27),
    );

    await _pumpSettingsDialog(
      tester,
      initialSectionId: 'projects',
      initialProjectId: 'project-2',
      extraOverrides: <dynamic>[
        projectRepositoryProvider.overrideWithValue(
          _FakeProjectRepository(projects),
        ),
        projectConfigServiceProvider.overrideWithValue(configService),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Projects'), findsWidgets);
    expect(find.text('/repo/second'), findsOneWidget);
    expect(find.text('/repo/first'), findsNothing);
  });
}
