part of 'settings_dialog_test.dart';

void _registerSettingsDialogAdvancedTests() {
  testWidgets('font autocomplete clears, toggles, and commits custom values', (
    tester,
  ) async {
    final container = await _pumpSettingsDialog(tester);
    await _selectTerminalSection(tester);

    final field = find.byKey(
      const ValueKey<String>('terminal-font-family-field'),
    );

    await tester.tap(field);
    await tester.pump();
    await tester.tap(find.byTooltip('Fonts'));
    await tester.pump();

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();

    await tester.enterText(field, 'Custom Mono');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.fontFamily,
      'Custom Mono',
    );
  });

  testWidgets('workspace directory browse commits the picked folder', (
    tester,
  ) async {
    final previousPlatform = FileSelectorPlatform.instance;
    final fakePlatform = _FakeFileSelectorPlatform(<Object?>[
      '/tmp/picked-workspaces',
    ]);
    FileSelectorPlatform.instance = fakePlatform;
    addTearDown(() => FileSelectorPlatform.instance = previousPlatform);

    final container = await _pumpSettingsDialog(tester);
    final field = find.byType(TextField).at(1);
    await tester.enterText(field, '/tmp/current-workspaces');
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Browse'));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsControllerProvider).general.workspaceDirectory,
      '/tmp/picked-workspaces',
    );
    expect(
      fakePlatform.requests.single.initialDirectory,
      '/tmp/current-workspaces',
    );
    expect(
      fakePlatform.requests.single.confirmButtonText,
      'Use as workspace directory',
    );
    expect(fakePlatform.requests.single.canCreateDirectories, isTrue);
  });

  testWidgets('font autocomplete supports arrow-up and numpad enter', (
    tester,
  ) async {
    final container = await _pumpSettingsDialog(tester);
    await _selectTerminalSection(tester);

    final field = find.byKey(
      const ValueKey<String>('terminal-font-family-field'),
    );
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, 'sf');
    await tester.pump();

    await tester.sendKeyDownEvent(.arrowUp);
    await tester.sendKeyUpEvent(.arrowUp);
    await tester.sendKeyDownEvent(.numpadEnter);
    await tester.sendKeyUpEvent(.numpadEnter);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.fontFamily,
      'SF Mono',
    );
  });

  testWidgets('keyboard search fallback and close actions dismiss the dialog', (
    tester,
  ) async {
    await _pumpSettingsDialog(tester);

    await tester.tap(find.text('Keyboard').first);
    await tester.pump();
    expect(find.text('When a Terminal Is Focused'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'confirm');
    await tester.pump();
    expect(find.text('Confirm Project Removal'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('no-results close button dismisses the dialog', (tester) async {
    await _pumpSettingsDialog(tester);

    await tester.enterText(find.byType(TextField).first, 'missing setting');
    await tester.pump();
    expect(find.text('No settings found.'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets(
    'word separators commits, clears, and resets from parent updates',
    (tester) async {
      final container = await _pumpSettingsDialog(tester);
      await _selectTerminalSection(tester);

      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == " ()[]{},\"'`",
      );

      await tester.enterText(field, '.,');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.wordSeparators,
        '.,',
      );

      await tester.enterText(field, '');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.wordSeparators,
        isNull,
      );

      await tester.enterText(field, 'abc');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.wordSeparators,
        'abc',
      );

      await container
          .read(settingsControllerProvider.notifier)
          .resetTerminalSettings();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        container.read(settingsControllerProvider).terminal.wordSeparators,
        isNull,
      );
      expect(tester.widget<TextField>(field).controller?.text, isEmpty);
    },
  );

  testWidgets(
    'font autocomplete covers closed-menu commits and hover selection',
    (tester) async {
      final container = await _pumpSettingsDialog(tester);
      await _selectTerminalSection(tester);

      final field = find.byKey(
        const ValueKey<String>('terminal-font-family-field'),
      );

      await tester.enterText(field, 'Custom Mono');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'sf');
      await tester.pump();
      await tester.tap(find.byTooltip('Fonts'));
      await tester.pump();

      await tester.sendKeyDownEvent(.arrowUp);
      await tester.sendKeyUpEvent(.arrowUp);
      await tester.sendKeyDownEvent(.numpadEnter);
      await tester.sendKeyUpEvent(.numpadEnter);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'SF Mono',
      );

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'Menlo Custom');
      await tester.pump();
      await tester.tap(find.byTooltip('Fonts'));
      await tester.pump();
      await tester.sendKeyDownEvent(.enter);
      await tester.sendKeyUpEvent(.enter);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'Menlo Custom',
      );

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'm');
      await tester.pump();

      final mouse = await tester.createGesture(kind: .mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(find.text('Menlo')));
      await tester.pump();
      await tester.sendKeyDownEvent(.enter);
      await tester.sendKeyUpEvent(.enter);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'Menlo',
      );

      await tester.tap(field);
      await tester.pump();
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      await tester.testTextInput.receiveAction(.done);
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'Menlo',
      );
      expect(tester.widget<AleraTextField>(field).controller?.text, 'Menlo');
    },
  );

  testWidgets('theme picker falls back and tracks hover state', (tester) async {
    final container = await _pumpSettingsDialog(
      tester,
      initialSettings: AleraSettings.defaults.copyWith(
        terminal: AleraSettings.defaults.terminal.copyWith(
          themeName: 'missing-theme',
        ),
      ),
    );
    await _selectTerminalSection(tester);

    expect(find.text('Selected: Alera Dark'), findsOneWidget);
    expect(find.text(r'$ git status --short'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('terminal-theme-search-field')),
      'drac',
    );
    await tester.pump();

    final mouse = await tester.createGesture(kind: .mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await tester.ensureVisible(find.text('Dracula'));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('Dracula')));
    await tester.pump();
    await tester.tap(find.text('Dracula'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.themeName,
      TerminalThemeNames.dracula,
    );
  });

  testWidgets(
    'workspace browse falls back to the stored directory when the field is empty',
    (tester) async {
      final previousPlatform = FileSelectorPlatform.instance;
      final fakePlatform = _FakeFileSelectorPlatform(<Object?>[
        '/tmp/fallback-picked-workspaces',
      ]);
      FileSelectorPlatform.instance = fakePlatform;
      addTearDown(() => FileSelectorPlatform.instance = previousPlatform);

      final container = await _pumpSettingsDialog(
        tester,
        initialSettings: AleraSettings.defaults.copyWith(
          general: AleraSettings.defaults.general.copyWith(
            workspaceDirectory: '/tmp/existing-workspaces',
          ),
        ),
      );
      final field = find.byType(TextField).at(1);

      await tester.enterText(field, '');
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Browse'));
      await tester.pumpAndSettle();

      expect(
        fakePlatform.requests.single.initialDirectory,
        '/tmp/existing-workspaces',
      );
      expect(
        container.read(settingsControllerProvider).general.workspaceDirectory,
        '/tmp/fallback-picked-workspaces',
      );
    },
  );

  testWidgets(
    'font autocomplete refreshes suggestions when async fonts arrive',
    (tester) async {
      final fontsCompleter = Completer<List<String>>();
      await _pumpSettingsDialog(
        tester,
        fontService: _DelayedSystemFontService(fontsCompleter.future),
      );
      await _selectTerminalSection(tester);

      final field = find.byKey(
        const ValueKey<String>('terminal-font-family-field'),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'alera');
      await tester.pump();

      expect(find.text('Alera Mono'), findsNothing);

      fontsCompleter.complete(<String>['Alera Mono']);
      await tester.pump();
      await tester.pump();

      expect(find.text('Alera Mono'), findsWidgets);
    },
  );

  testWidgets(
    'hex color fields commit, clear invalid input, and reset on updates',
    (tester) async {
      final container = await _pumpSettingsDialog(tester);
      await _selectTerminalSection(tester);

      final field = find.byWidgetPredicate(
        (widget) => widget is AleraTextField && widget.hintText == '#101010',
      );
      await tester.ensureVisible(field);
      await tester.pump();

      await tester.enterText(field, '#123456');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container
            .read(settingsControllerProvider)
            .terminal
            .colorOverrides
            .background,
        '#123456',
      );

      await tester.enterText(field, '');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container
            .read(settingsControllerProvider)
            .terminal
            .colorOverrides
            .background,
        isNull,
      );

      await tester.enterText(field, 'bad');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<AleraTextField>(field).controller?.text, isEmpty);

      await tester.enterText(field, '#abcdef');
      await tester.testTextInput.receiveAction(.done);
      await tester.pump(const Duration(milliseconds: 50));

      await container
          .read(settingsControllerProvider.notifier)
          .resetTerminalSettings();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        container
            .read(settingsControllerProvider)
            .terminal
            .colorOverrides
            .background,
        isNull,
      );
      expect(tester.widget<AleraTextField>(field).controller?.text, isEmpty);
    },
  );
}
