part of 'add_project_dialog_test.dart';

void _registerAddProjectDialogLocalTests() {
  testWidgets('submits a local folder project', (tester) async {
    AddProjectResult? result;

    await _pumpDialogLauncher(tester, onResult: (value) => result = value);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Project path'),
      '/projects/notes',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add project'));
    await tester.pumpAndSettle();

    expect(result, isA<AddLocalProjectResult>());
    final local = result! as AddLocalProjectResult;
    expect(local.path, '/projects/notes');
    expect(local.name, 'notes');
  });

  testWidgets('submits a clone-from-URL project', (tester) async {
    AddProjectResult? result;

    await _pumpDialogLauncher(tester, onResult: (value) => result = value);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clone from URL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Git URL'),
      'https://github.com/acme/alera.git',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Destination folder'),
      '/projects/alera',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add project'));
    await tester.pumpAndSettle();

    expect(result, isA<CloneProjectResult>());
    final clone = result! as CloneProjectResult;
    expect(clone.gitUrl, 'https://github.com/acme/alera.git');
    expect(clone.destinationPath, '/projects/alera');
    expect(clone.name, 'alera');
  });

  testWidgets(
    'updates derived names when switching modes and preserves manual edits',
    (tester) async {
      await _pumpDialogLauncher(tester, onResult: (_) {});

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Project path'),
        '/projects/notes',
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Display name (optional)'),
            )
            .controller
            ?.text,
        'notes',
      );

      await tester.tap(find.text('Clone from URL'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Git URL'),
        'https://github.com/acme/platform.git?ref=main',
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Display name (optional)'),
            )
            .controller
            ?.text,
        'platform',
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Display name (optional)'),
        'My platform',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Git URL'),
        'https://github.com/acme/renamed.git/',
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Display name (optional)'),
            )
            .controller
            ?.text,
        'My platform',
      );

      await tester.tap(find.text('Local folder'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Display name (optional)'),
            )
            .controller
            ?.text,
        'My platform',
      );
    },
  );

  testWidgets('disables submission until required inputs and supports cancel', (
    tester,
  ) async {
    AddProjectResult? result;

    await _pumpDialogLauncher(tester, onResult: (value) => result = value);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    FilledButton addProjectButton() =>
        tester.widget(find.widgetWithText(FilledButton, 'Add project'));

    expect(addProjectButton().onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Project path'),
      '/projects/notes',
    );
    await tester.pumpAndSettle();
    expect(addProjectButton().onPressed, isNotNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Project path'),
      '   ',
    );
    await tester.pumpAndSettle();
    expect(addProjectButton().onPressed, isNull);

    await tester.tap(find.text('Clone from URL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Git URL'),
      'https://github.com/acme/alera.git',
    );
    await tester.pumpAndSettle();
    expect(addProjectButton().onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Destination folder'),
      '/projects/alera',
    );
    await tester.pumpAndSettle();
    expect(addProjectButton().onPressed, isNotNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('submits the local form from the keyboard', (tester) async {
    AddProjectResult? result;

    await _pumpDialogLauncher(tester, onResult: (value) => result = value);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Project path'),
      '/projects/keyboard',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(result, isA<AddLocalProjectResult>());
    expect((result! as AddLocalProjectResult).path, '/projects/keyboard');
  });

  testWidgets('renders the progress dialog message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AddProjectProgressDialog(message: 'Cloning repository…'),
        ),
      ),
    );

    expect(find.text('Cloning repository…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('local browse shows picker errors and then fills path defaults', (
    tester,
  ) async {
    final previousPlatform = FileSelectorPlatform.instance;
    final fakePlatform = _FakeFileSelectorPlatform(<Object?>[
      StateError('picker unavailable'),
      '/projects/from-picker',
    ]);
    FileSelectorPlatform.instance = fakePlatform;
    addTearDown(() => FileSelectorPlatform.instance = previousPlatform);

    await _pumpDialogLauncher(tester, onResult: (_) {});

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Browse'));
    await tester.pump();
    expect(fakePlatform.requests, hasLength(1));

    await tester.tap(find.byTooltip('Browse'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Project path'))
          .controller
          ?.text,
      '/projects/from-picker',
    );
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Display name (optional)'),
          )
          .controller
          ?.text,
      'from-picker',
    );
    expect(fakePlatform.requests.first.confirmButtonText, 'Select folder');
  });
}
