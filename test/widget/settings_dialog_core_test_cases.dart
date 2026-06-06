part of 'settings_dialog_test.dart';

void _registerSettingsDialogCoreTests() {
  Future<ProviderContainer> pumpSettingsDialogLocal(
    WidgetTester tester, {
    _FakeGitHubStarController? starController,
    AleraSettings initialSettings = AleraSettings.defaults,
    Size surfaceSize = const Size(1200, 900),
    SystemFontService? fontService,
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeSettingsRepository(initialSettings);
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repository),
        systemFontServiceProvider.overrideWithValue(
          fontService ??
              const _FakeSystemFontService(<String>[
                'Fira Code',
                'Menlo',
                'SF Mono',
              ]),
        ),
        aleraUpdateServiceProvider.overrideWithValue(_FakeUpdateService()),
        if (starController != null)
          gitHubStarControllerProvider.overrideWith(() => starController),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const SettingsDialog(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  Future<void> selectTerminalSectionLocal(WidgetTester tester) async {
    // The sidebar lists General and Terminal — tap the Terminal nav item to
    // switch content. The first 'Terminal' text in the tree belongs to the
    // sidebar nav item (the section header inside the content uses titleLarge
    // and shows only when active).
    await tester.tap(find.text('Terminal').first);
    await tester.pump();
  }

  Future<void> selectEditorSectionLocal(WidgetTester tester) async {
    await tester.tap(find.text('Editor').first);
    await tester.pump();
  }

  testWidgets('shows terminal settings and filters with search', (
    tester,
  ) async {
    await pumpSettingsDialogLocal(tester);

    expect(find.text('Updates'), findsOneWidget);

    await selectTerminalSectionLocal(tester);

    expect(find.text('Terminal'), findsWidgets);
    expect(find.text('Font family'), findsOneWidget);
    expect(find.text('Theme preset'), findsOneWidget);
    expect(find.text('Scrollback lines'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'cursor');
    await tester.pump();

    expect(find.text('Terminal'), findsWidgets);
    expect(find.text('Cursor shape'), findsOneWidget);
    expect(find.text('Cursor opacity'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'missing setting');
    await tester.pump();

    expect(find.text('No settings found.'), findsOneWidget);
  });

  testWidgets('edits and resets editor settings', (tester) async {
    final container = await pumpSettingsDialogLocal(tester);
    await selectEditorSectionLocal(tester);

    expect(find.text('Editor'), findsWidgets);
    expect(find.text('Tab size'), findsOneWidget);
    expect(find.text('Theme preset'), findsOneWidget);
    expect(container.read(settingsControllerProvider).editor.tabSize, 4);
    expect(
      container.read(settingsControllerProvider).editor.themeName,
      EditorSyntaxThemeNames.alera,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('editor-theme-search-field')),
      'monokai',
    );
    await tester.pump();
    await tester.tap(find.text(EditorSyntaxThemeNames.monokai));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).editor.themeName,
      EditorSyntaxThemeNames.monokai,
    );

    await tester.ensureVisible(find.text('Tab size'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(settingsControllerProvider).editor.tabSize, 2);

    await tester.tap(find.text('Reset editor'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).editor.tabSize,
      EditorSettings.defaults.tabSize,
    );
    expect(
      container.read(settingsControllerProvider).editor.themeName,
      EditorSettings.defaults.themeName,
    );
  });

  testWidgets('edits and resets terminal settings', (tester) async {
    final container = await pumpSettingsDialogLocal(tester);
    await selectTerminalSectionLocal(tester);

    await tester.enterText(find.byType(TextField).at(2), '18');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(settingsControllerProvider).terminal.fontSize, 18);

    await tester.tap(
      find.byKey(const ValueKey<String>('terminal-font-family-field')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('terminal-font-family-field')),
      'Men',
    );
    await tester.pump();
    await tester.tap(find.text('Menlo'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.fontFamily,
      'Menlo',
    );

    await tester.ensureVisible(find.byTooltip('Bar'));
    await tester.pump();
    await tester.tap(find.byTooltip('Bar'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.cursorShape,
      TerminalCursorShape.bar,
    );

    await tester.ensureVisible(find.text('Blinking cursor'));
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.cursorBlink,
      isTrue,
    );

    await tester.ensureVisible(find.text('Theme preset'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('terminal-theme-search-field')),
      'dracula',
    );
    await tester.pump();
    await tester.tap(find.text('Dracula'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.themeName,
      TerminalThemeNames.dracula,
    );

    await tester.dragFrom(const Offset(500, 240), const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset terminal'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.fontSize,
      TerminalSettings.defaults.fontSize,
    );
    expect(
      container.read(settingsControllerProvider).terminal.cursorShape,
      TerminalCursorShape.block,
    );
    expect(
      container.read(settingsControllerProvider).terminal.themeName,
      TerminalSettings.defaults.themeName,
    );
  });

  testWidgets('theme picker stacks preview below the list on narrow widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 540,
            child: buildThemePickerSettingForTesting(
              value: TerminalThemeNames.aleraDark,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('terminal-theme-search-field')),
      findsOneWidget,
    );
    expect(find.text('Theme preset'), findsOneWidget);
  });

  testWidgets('edits destructive confirmation settings', (tester) async {
    final container = await pumpSettingsDialogLocal(tester);

    expect(find.text('Safety'), findsOneWidget);
    expect(find.text('Confirm project removal'), findsOneWidget);
    expect(find.text('Confirm workspace removal'), findsOneWidget);

    await tester.tap(find.byType(Switch).at(0));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).general.confirmProjectRemoval,
      isFalse,
    );

    await tester.tap(find.byType(Switch).at(1));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container
          .read(settingsControllerProvider)
          .general
          .confirmWorkspaceRemoval,
      isFalse,
    );

    await tester.enterText(find.byType(TextField).first, 'destructive');
    await tester.pump();

    expect(find.text('Confirm project removal'), findsOneWidget);
    expect(find.text('Confirm workspace removal'), findsOneWidget);
  });

  testWidgets('edits agent status notification and awake settings', (
    tester,
  ) async {
    final container = await pumpSettingsDialogLocal(tester);

    await tester.ensureVisible(find.text('Agent status notifications'));
    await tester.pump();

    expect(find.text('Codex hooks'), findsOneWidget);
    expect(find.text('Claude Code hooks'), findsOneWidget);
    expect(find.text('GitHub Copilot hooks'), findsOneWidget);
    expect(find.text('Cursor hooks'), findsOneWidget);
    expect(find.text('Antigravity hooks'), findsOneWidget);
    expect(find.text('OpenCode hooks'), findsOneWidget);
    expect(find.text('Pi hooks'), findsOneWidget);
    expect(find.text('Amp hooks'), findsOneWidget);
    expect(find.text('Agent status notifications'), findsOneWidget);
    expect(
      find.text('Keep computer awake while agents are working'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Codex hooks'));
    await tester.pump();
    await tester.tap(find.byType(Switch).at(2));
    await tester.pump(const Duration(milliseconds: 50));
    for (final entry in const <({String label, int switchIndex})>[
      (label: 'Claude Code hooks', switchIndex: 3),
      (label: 'GitHub Copilot hooks', switchIndex: 4),
      (label: 'Cursor hooks', switchIndex: 5),
      (label: 'Antigravity hooks', switchIndex: 6),
      (label: 'OpenCode hooks', switchIndex: 7),
      (label: 'Pi hooks', switchIndex: 8),
      (label: 'Amp hooks', switchIndex: 9),
    ]) {
      await tester.ensureVisible(find.text(entry.label));
      await tester.pump();
      await tester.tap(find.byType(Switch).at(entry.switchIndex));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.ensureVisible(find.text('Agent status notifications'));
    await tester.pump();
    await tester.tap(find.byType(Switch).at(10));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.ensureVisible(
      find.text('Keep computer awake while agents are working'),
    );
    await tester.pump();
    await tester.tap(find.byType(Switch).at(11));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).general.agentStatusHooks.codex,
      isTrue,
    );
    expect(
      container
          .read(settingsControllerProvider)
          .general
          .agentStatusHooks
          .claude,
      isTrue,
    );
    expect(
      container
          .read(settingsControllerProvider)
          .general
          .agentStatusHooks
          .copilot,
      isTrue,
    );
    expect(
      container
          .read(settingsControllerProvider)
          .general
          .agentStatusHooks
          .cursor,
      isTrue,
    );
    expect(
      container.read(settingsControllerProvider).general.agentStatusHooks.agy,
      isTrue,
    );
    expect(
      container
          .read(settingsControllerProvider)
          .general
          .agentStatusHooks
          .opencode,
      isTrue,
    );
    expect(
      container.read(settingsControllerProvider).general.agentStatusHooks.pi,
      isTrue,
    );
    expect(
      container.read(settingsControllerProvider).general.agentStatusHooks.amp,
      isTrue,
    );
    expect(
      container
          .read(settingsControllerProvider)
          .general
          .agentStatusNotificationsEnabled,
      isTrue,
    );
    expect(
      container
          .read(settingsControllerProvider)
          .general
          .keepComputerAwakeWhileAgentsWork,
      isTrue,
    );

    await tester.enterText(find.byType(TextField).first, 'notification');
    await tester.pump();

    expect(find.text('Agent status notifications'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'awake');
    await tester.pump();

    expect(
      find.text('Keep computer awake while agents are working'),
      findsOneWidget,
    );
  });

  testWidgets('edits terminal color override via color picker dialog', (
    tester,
  ) async {
    final container = await pumpSettingsDialogLocal(tester);
    await selectTerminalSectionLocal(tester);

    // Verify initial state: no foreground color override
    expect(
      container
          .read(settingsControllerProvider)
          .terminal
          .colorOverrides
          .foreground,
      isNull,
    );

    // Find the first color swatch (Foreground color swatch)
    final swatchFinder = find.byType(AleraColorSwatch).first;
    expect(swatchFinder, findsOneWidget);

    // Ensure the color swatch is visible
    await tester.ensureVisible(swatchFinder);
    await tester.pumpAndSettle();

    // Tap it to open the color picker dialog
    await tester.tap(swatchFinder);
    await tester.pumpAndSettle();

    // Verify the dialog has opened
    expect(find.text('Foreground color'), findsWidgets); // dialog title
    expect(find.byType(ColorPicker), findsOneWidget);

    // Simulate changing color in the picker to #112233
    final ColorPicker pickerWidget = tester.widget(find.byType(ColorPicker));
    pickerWidget.onColorChanged(const Color(0xFF112233));
    await tester.pump();

    // Tap Select
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    // Verify color override is updated to #112233
    expect(
      container
          .read(settingsControllerProvider)
          .terminal
          .colorOverrides
          .foreground,
      '#112233',
    );
  });

  testWidgets(
    'font autocomplete supports keyboard selection and empty-state dismissal',
    (tester) async {
      final container = await pumpSettingsDialogLocal(tester);
      await selectTerminalSectionLocal(tester);

      final field = find.byKey(
        const ValueKey<String>('terminal-font-family-field'),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'sf');
      await tester.pump();

      expect(find.text('SF Mono'), findsWidgets);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'SF Mono',
      );

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'zzz');
      await tester.pump();

      expect(find.text('No matching fonts.'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.text('No matching fonts.'), findsNothing);
    },
  );

  testWidgets('workspace directory commits and clears overrides', (
    tester,
  ) async {
    final container = await pumpSettingsDialogLocal(tester);
    final field = find.byType(TextField).at(1);

    await tester.enterText(field, '/tmp/alera-workspaces');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).general.workspaceDirectory,
      '/tmp/alera-workspaces',
    );

    await tester.enterText(field, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).general.workspaceDirectory,
      isNull,
    );
  });

  testWidgets(
    'support section can star Alera from not-starred and error states',
    (tester) async {
      final container = await pumpSettingsDialogLocal(
        tester,
        starController: _FakeGitHubStarController(
          GitHubStarState.notStarred,
          nextStarState: GitHubStarState.starred,
        ),
      );

      expect(find.text('Support Alera'), findsOneWidget);
      expect(find.text('Star'), findsOneWidget);

      await tester.ensureVisible(find.text('Star'));
      await tester.pump();
      await tester.tap(find.text('Star'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Thanks for the support!'), findsOneWidget);

      final errorController = _FakeGitHubStarController(
        GitHubStarState.error,
        nextStarState: GitHubStarState.starred,
      );
      container.dispose();
      await pumpSettingsDialogLocal(tester, starController: errorController);

      expect(find.text('Try again'), findsOneWidget);

      await tester.ensureVisible(find.text('Try again'));
      await tester.pump();
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Thanks for the support!'), findsOneWidget);
    },
  );

  testWidgets('support section hides itself when starring is unavailable', (
    tester,
  ) async {
    await pumpSettingsDialogLocal(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
    );

    expect(find.text('Support Alera'), findsNothing);
    expect(find.byKey(const ValueKey<String>('hidden')), findsNothing);
  });

  testWidgets('hidden star control shrinks away', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildStarControlForTesting(
            state: GitHubStarState.hidden,
            onStar: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('hidden')), findsOneWidget);
  });
}
