part of 'add_project_dialog_test.dart';

void _registerAddProjectDialogCloneTests() {
  testWidgets('clone parent browse derives the destination folder', (
    tester,
  ) async {
    final previousPlatform = FileSelectorPlatform.instance;
    final fakePlatform = _FakeFileSelectorPlatform(<Object?>['/projects']);
    FileSelectorPlatform.instance = fakePlatform;
    addTearDown(() => FileSelectorPlatform.instance = previousPlatform);

    await _pumpDialogLauncher(tester, onResult: (_) {});

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clone from URL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Git URL'),
      'https://github.com/acme/alera.git',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Choose parent folder'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Destination folder'),
          )
          .controller
          ?.text,
      '/projects/alera',
    );
    expect(
      fakePlatform.requests.single.confirmButtonText,
      'Select parent folder',
    );
    expect(fakePlatform.requests.single.canCreateDirectories, isTrue);
  });

  testWidgets('clone parent browse shows picker errors', (tester) async {
    final previousPlatform = FileSelectorPlatform.instance;
    final fakePlatform = _FakeFileSelectorPlatform(<Object?>[
      StateError('picker unavailable'),
    ]);
    FileSelectorPlatform.instance = fakePlatform;
    addTearDown(() => FileSelectorPlatform.instance = previousPlatform);
    final toasts = <AleraToastData>[];
    final sub = AleraToast.stream.listen(toasts.add);
    addTearDown(sub.cancel);

    await _pumpDialogLauncher(tester, onResult: (_) {});

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clone from URL'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Choose parent folder'));
    await tester.pump();

    expect(toasts, hasLength(1));
    expect(
      toasts.single.message,
      'Native folder picker is not available; paste path manually.',
    );
  });

  testWidgets('submits the clone form from the Git URL field', (tester) async {
    AddProjectResult? result;

    await _pumpDialogLauncher(tester, onResult: (value) => result = value);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clone from URL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Git URL'),
      'https://github.com/acme/from-url.git',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Destination folder'),
      '/projects/from-url',
    );
    await tester.tap(find.widgetWithText(TextField, 'Git URL'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(result, isA<CloneProjectResult>());
    expect(
      (result! as CloneProjectResult).destinationPath,
      '/projects/from-url',
    );
  });

  testWidgets('submits the clone form from the destination field', (
    tester,
  ) async {
    AddProjectResult? result;

    await _pumpDialogLauncher(tester, onResult: (value) => result = value);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clone from URL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Git URL'),
      'https://github.com/acme/from-destination.git',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Destination folder'),
      '/projects/from-destination',
    );
    await tester.tap(find.widgetWithText(TextField, 'Destination folder'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(result, isA<CloneProjectResult>());
    expect((result! as CloneProjectResult).name, 'from-destination');
  });

  testWidgets(
    'switching back to local mode clears untouched names when no path is set',
    (tester) async {
      await _pumpDialogLauncher(tester, onResult: (_) {});

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clone from URL'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Git URL'),
        'https://github.com/acme/cleared.git',
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Display name (optional)'),
            )
            .controller
            ?.text,
        'cleared',
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
        '',
      );
    },
  );

  testWidgets(
    'submits the local form from the display-name field and preserves manual names',
    (tester) async {
      AddProjectResult? result;

      await _pumpDialogLauncher(tester, onResult: (value) => result = value);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Project path'),
        '/projects/manual-name',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Display name (optional)'),
        'Pinned name',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Project path'),
        '/projects/manual-name-renamed',
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Display name (optional)'),
            )
            .controller
            ?.text,
        'Pinned name',
      );

      await tester.tap(
        find.widgetWithText(TextField, 'Display name (optional)'),
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(result, isA<AddLocalProjectResult>());
      final local = result! as AddLocalProjectResult;
      expect(local.path, '/projects/manual-name-renamed');
      expect(local.name, 'Pinned name');
    },
  );
}
