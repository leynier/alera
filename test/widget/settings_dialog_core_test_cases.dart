part of 'settings_dialog_test.dart';

void _registerSettingsDialogCoreTests() {
  Future<ProviderContainer> pumpSettingsDialogLocal(
    WidgetTester tester, {
    _FakeGitHubStarController? starController,
    AleraSettings initialSettings = AleraSettings.defaults,
    Size surfaceSize = const Size(1200, 900),
    SystemFontService? fontService,
    AiTextModelDiscoveryService? modelDiscoveryService,
    List<dynamic> extraOverrides = const <dynamic>[],
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Keep MediaQuery in sync with the surface so the adaptive dialog sizing
    // (width/height fractions) sees the intended screen size.
    tester.view.physicalSize = surfaceSize * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
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
        aiTextModelDiscoveryServiceProvider.overrideWithValue(
          modelDiscoveryService ?? const _FakeAiTextModelDiscoveryService(),
        ),
        if (starController != null)
          gitHubStarControllerProvider.overrideWith(() => starController),
        ...extraOverrides,
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

  Future<void> selectAiTextSectionLocal(WidgetTester tester) async {
    await tester.tap(find.text('AI Text').first);
    await tester.pump();
  }

  testWidgets('shows terminal settings and filters with search', (
    tester,
  ) async {
    await pumpSettingsDialogLocal(tester);

    // 'Updates' appears both as a subsection chip and as the group title.
    expect(find.text('Updates'), findsWidgets);

    await selectTerminalSectionLocal(tester);

    expect(find.text('Terminal'), findsWidgets);
    expect(find.text('Font Family'), findsOneWidget);
    expect(find.text('Theme Preset'), findsOneWidget);
    expect(find.text('TUI Scroll Speed'), findsOneWidget);
    expect(find.text('Copy On Select'), findsOneWidget);
    expect(find.text('Allow OSC 52 Clipboard Writes'), findsOneWidget);
    expect(find.text('Scrollback Lines'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'cursor');
    await tester.pump();

    expect(find.text('Terminal'), findsWidgets);
    expect(find.text('Cursor Shape'), findsOneWidget);
    expect(find.text('Cursor Opacity'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'missing setting');
    await tester.pump();

    expect(find.text('No settings found.'), findsOneWidget);
  });

  testWidgets('edits project setup config overrides', (tester) async {
    final project = Project(
      id: 'project-1',
      name: 'Alera',
      repoPath: '/repo/alera',
      createdAt: DateTime.utc(2026, 6, 27),
      updatedAt: DateTime.utc(2026, 6, 27),
    );
    final configRepository = FakeProjectConfigRepository();
    addTearDown(configRepository.dispose);
    final configService = ProjectConfigService(
      repository: configRepository,
      fileStore: FakeProjectConfigFileStore(),
      now: () => DateTime.utc(2026, 6, 27),
    );
    await pumpSettingsDialogLocal(
      tester,
      extraOverrides: <dynamic>[
        projectRepositoryProvider.overrideWithValue(
          _FakeProjectRepository(<Project>[project]),
        ),
        projectConfigServiceProvider.overrideWithValue(configService),
      ],
    );

    await tester.tap(find.text('Projects').first);
    await tester.pumpAndSettle();

    expect(find.text('Alera'), findsWidgets);
    expect(find.text('Add Copy Rule'), findsOneWidget);

    await tester.ensureVisible(find.text('Add Copy Rule'));
    await tester.pump();
    await tester.tap(find.text('Add Copy Rule'));
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('copy-rule-from-field')),
        matching: find.byType(TextField),
      ),
      '.env',
    );
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('copy-rule-to-field')),
        matching: find.byType(TextField),
      ),
      '.env.local',
    );
    await tester.pump();
    await tester.ensureVisible(find.byType(AleraCheckbox).first);
    await tester.pump();
    await tester.tap(find.byType(AleraCheckbox).first);
    await tester.pump();
    await tester.ensureVisible(find.text('Add Setup Command'));
    await tester.pump();
    await tester.tap(find.text('Add Setup Command'));
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('setup-command-field')),
        matching: find.byType(TextField),
      ),
      'pnpm install',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save Override'));
    await tester.pump();
    await tester.tap(find.text('Save Override'));
    await tester.pump();

    final saved = configRepository.configs[project.id]!;
    expect(saved.worktree.copy.single.from, '.env');
    expect(saved.worktree.copy.single.to, '.env.local');
    expect(saved.worktree.copy.single.overwrite, isTrue);
    expect(saved.worktree.setup, <String>['pnpm install']);
  });

  testWidgets('clears dirty project setup edits when using repo file', (
    tester,
  ) async {
    final project = Project(
      id: 'project-1',
      name: 'Alera',
      repoPath: '/repo/alera',
      createdAt: DateTime.utc(2026, 6, 27),
      updatedAt: DateTime.utc(2026, 6, 27),
    );
    final configRepository = FakeProjectConfigRepository();
    addTearDown(configRepository.dispose);
    await configRepository.save(
      projectId: project.id,
      config: ProjectConfig.empty,
      updatedAt: DateTime.utc(2026, 6, 27),
    );
    final configService = ProjectConfigService(
      repository: configRepository,
      fileStore: FakeProjectConfigFileStore(),
      now: () => DateTime.utc(2026, 6, 27),
    );
    await pumpSettingsDialogLocal(
      tester,
      extraOverrides: <dynamic>[
        projectRepositoryProvider.overrideWithValue(
          _FakeProjectRepository(<Project>[project]),
        ),
        projectConfigServiceProvider.overrideWithValue(configService),
      ],
    );

    await tester.tap(find.text('Projects').first);
    await tester.pumpAndSettle();
    expect(find.text('UI Override'), findsWidgets);

    await tester.ensureVisible(find.text('Add Setup Command'));
    await tester.pump();
    await tester.tap(find.text('Add Setup Command'));
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('setup-command-field')),
        matching: find.byType(TextField),
      ),
      'pnpm install',
    );
    await tester.pump();
    expect(find.text('pnpm install'), findsOneWidget);

    await tester.ensureVisible(find.text('Use Repo File'));
    await tester.pump();
    await tester.tap(find.text('Use Repo File'));
    await tester.pumpAndSettle();

    expect(configRepository.configs.containsKey(project.id), isFalse);
    expect(find.text('None'), findsWidgets);
    expect(find.text('No Setup Commands'), findsOneWidget);
    expect(find.text('pnpm install'), findsNothing);
  });

  testWidgets('edits and resets editor settings', (tester) async {
    final container = await pumpSettingsDialogLocal(tester);
    await selectEditorSectionLocal(tester);

    expect(find.text('Editor'), findsWidgets);
    expect(find.text('Tab Size'), findsOneWidget);
    expect(find.text('Theme Preset'), findsOneWidget);
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

    await tester.ensureVisible(find.text('Tab Size'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(settingsControllerProvider).editor.tabSize, 2);

    await tester.tap(find.text('Reset Editor'));
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

  testWidgets('edits and resets AI text settings', (tester) async {
    final container = await pumpSettingsDialogLocal(tester);
    await selectAiTextSectionLocal(tester);

    expect(find.text('AI Text'), findsWidgets);
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(
      tester
          .widgetList<MouseRegion>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('ai-text-agent-codex')),
              matching: find.byType(MouseRegion),
            ),
          )
          .first
          .cursor,
      SystemMouseCursors.click,
    );
    expect(
      tester
          .widgetList<MouseRegion>(
            find.descendant(
              of: find.byKey(
                const ValueKey<String>('ai-text-model-codex-gpt-5.5'),
              ),
              matching: find.byType(MouseRegion),
            ),
          )
          .first
          .cursor,
      SystemMouseCursors.click,
    );
    expect(
      tester
          .widgetList<MouseRegion>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('ai-text-thinking-low')),
              matching: find.byType(MouseRegion),
            ),
          )
          .first
          .cursor,
      SystemMouseCursors.click,
    );

    await tester.tap(find.byKey(const ValueKey<String>('ai-text-agent-codex')));
    await tester.pumpAndSettle();
    expect(
      find.byType(AleraDropdownEntry<AiTextGenerationAgent>),
      findsWidgets,
    );
    expect(
      tester
          .widgetList<AleraDropdownEntry<AiTextGenerationAgent>>(
            find.byType(AleraDropdownEntry<AiTextGenerationAgent>),
          )
          .first
          .enabled,
      isTrue,
    );
    await tester.tap(find.text('Antigravity').last);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).aiTextGeneration.agent,
      AiTextGenerationAgent.agy,
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      container
          .read(settingsControllerProvider)
          .aiTextGeneration
          .discoveredModelsFor(AiTextGenerationAgent.agy)
          .map((model) => model.id),
      contains('gpt-5.5'),
    );

    await tester.tap(find.text('Reset AI Text'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).aiTextGeneration.agent,
      AiTextGenerationSettings.defaults.agent,
    );
    expect(find.text('Codex').last, findsOneWidget);

    await tester.ensureVisible(find.text('Commit Messages'));
    expect(find.text('Pull Request Details'), findsOneWidget);
    expect(find.text('Branch Names'), findsNothing);
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Optional instructions').first,
      'Use conventional commits.',
    );
    await selectTerminalSectionLocal(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container
          .read(settingsControllerProvider)
          .aiTextGeneration
          .instructionsFor(AiTextGenerationOperation.commitMessage),
      'Use conventional commits.',
    );

    await container
        .read(settingsControllerProvider.notifier)
        .resetAiTextGenerationSettings();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).aiTextGeneration.agent,
      AiTextGenerationSettings.defaults.agent,
    );

    await selectAiTextSectionLocal(tester);
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Optional instructions').first,
      'Draft that should not survive reset.',
    );
    await tester.ensureVisible(find.text('Reset AI Text', skipOffstage: false));
    await tester.pump();
    await tester.tap(find.text('Reset AI Text'));
    await tester.pump(const Duration(milliseconds: 50));
    await selectTerminalSectionLocal(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container
          .read(settingsControllerProvider)
          .aiTextGeneration
          .instructionsFor(AiTextGenerationOperation.commitMessage),
      isEmpty,
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

    await tester.ensureVisible(find.text('Blinking Cursor'));
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).terminal.cursorBlink,
      isTrue,
    );

    await tester.ensureVisible(find.text('Theme Preset'));
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
    await tester.tap(find.text('Reset Terminal'));
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
    expect(find.text('Theme Preset'), findsOneWidget);
  });

  testWidgets('edits destructive confirmation settings', (tester) async {
    final container = await pumpSettingsDialogLocal(tester);

    // 'Safety' appears both as a subsection chip and as the group title.
    expect(find.text('Safety'), findsWidgets);
    expect(find.text('Confirm Project Removal'), findsOneWidget);
    expect(find.text('Confirm Workspace Removal'), findsOneWidget);

    await tester.ensureVisible(find.byType(Switch).at(0));
    await tester.pump();
    await tester.tap(find.byType(Switch).at(0));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(settingsControllerProvider).general.confirmProjectRemoval,
      isFalse,
    );

    await tester.ensureVisible(find.byType(Switch).at(1));
    await tester.pump();
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

    expect(find.text('Confirm Project Removal'), findsOneWidget);
    expect(find.text('Confirm Workspace Removal'), findsOneWidget);
  });

  testWidgets('edits agent status notification and awake settings', (
    tester,
  ) async {
    final container = await pumpSettingsDialogLocal(tester);

    // Agent hooks and behavior settings live in the Agents section.
    await tester.tap(find.text('Agents').first);
    await tester.pump();

    await tester.ensureVisible(find.text('Agent Status Notifications'));
    await tester.pump();

    for (final label in const <String>[
      'Codex Hooks',
      'Claude Code Hooks',
      'GitHub Copilot Hooks',
      'Cursor Hooks',
      'Antigravity Hooks',
      'OpenCode Hooks',
      'Pi Hooks',
      'Amp Hooks',
      'Grok Build Hooks',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Agent Status Notifications'), findsOneWidget);
    expect(
      find.text('Keep Computer Awake While Agents Are Working'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Codex Hooks'));
    await tester.pump();
    await tester.tap(find.byType(Switch).at(0));
    await tester.pump(const Duration(milliseconds: 50));
    for (final entry in const <({String label, int switchIndex})>[
      (label: 'Claude Code Hooks', switchIndex: 1),
      (label: 'GitHub Copilot Hooks', switchIndex: 2),
      (label: 'Cursor Hooks', switchIndex: 3),
      (label: 'Antigravity Hooks', switchIndex: 4),
      (label: 'OpenCode Hooks', switchIndex: 5),
      (label: 'Pi Hooks', switchIndex: 6),
      (label: 'Amp Hooks', switchIndex: 7),
      (label: 'Grok Build Hooks', switchIndex: 8),
    ]) {
      await tester.ensureVisible(find.text(entry.label));
      await tester.pump();
      await tester.tap(find.byType(Switch).at(entry.switchIndex));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.ensureVisible(find.text('Agent Status Notifications'));
    await tester.pump();
    await tester.tap(find.byType(Switch).at(9));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.ensureVisible(
      find.text('Keep Computer Awake While Agents Are Working'),
    );
    await tester.pump();
    await tester.tap(find.byType(Switch).at(10));
    await tester.pump(const Duration(milliseconds: 50));

    final hooks = container
        .read(settingsControllerProvider)
        .agents
        .agentStatusHooks;
    expect(<bool>[
      hooks.codex,
      hooks.claude,
      hooks.copilot,
      hooks.cursor,
      hooks.agy,
      hooks.opencode,
      hooks.pi,
      hooks.amp,
      hooks.grok,
    ], everyElement(isTrue));
    expect(
      container
          .read(settingsControllerProvider)
          .agents
          .agentStatusNotificationsEnabled,
      isTrue,
    );
    expect(
      container
          .read(settingsControllerProvider)
          .agents
          .keepComputerAwakeWhileAgentsWork,
      isTrue,
    );

    await tester.enterText(find.byType(TextField).first, 'notification');
    await tester.pump();

    expect(find.text('Agent Status Notifications'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'awake');
    await tester.pump();

    expect(
      find.text('Keep Computer Awake While Agents Are Working'),
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
    expect(find.text('Foreground Color'), findsWidgets); // dialog title
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

  testWidgets('sidebar groups sections under Preferences and Resources', (
    tester,
  ) async {
    await pumpSettingsDialogLocal(tester);

    // AleraSectionHeader renders group labels uppercased.
    expect(find.text('PREFERENCES'), findsOneWidget);
    expect(find.text('RESOURCES'), findsOneWidget);
    expect(find.text('Application'), findsWidgets);
    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('General'), findsNothing);

    // Let pending timers (tooltips, animations) finish before teardown.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('tapping a subsection chip scrolls its group into view', (
    tester,
  ) async {
    await pumpSettingsDialogLocal(tester);
    await selectTerminalSectionLocal(tester);

    // 'Advanced' appears as a header chip and as the (initially offscreen)
    // group title further down the pane.
    final advancedTexts = find.text('Advanced', skipOffstage: false);
    expect(advancedTexts, findsNWidgets(2));

    final chip = advancedTexts.first;
    final groupTitle = advancedTexts.last;
    final beforeDy = tester.getTopLeft(groupTitle).dy;

    await tester.tap(chip);
    await tester.pumpAndSettle();

    final afterDy = tester.getTopLeft(groupTitle).dy;
    expect(afterDy, lessThan(beforeDy));
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(afterDy, lessThan(screenHeight));
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
