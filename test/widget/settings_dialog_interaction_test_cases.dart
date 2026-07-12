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
    await tester.testTextInput.receiveAction(TextInputAction.done);
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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.numpadEnter);
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
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.wordSeparators,
        '.,',
      );

      await tester.enterText(field, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.wordSeparators,
        isNull,
      );

      await tester.enterText(field, 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
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
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'sf');
      await tester.pump();
      await tester.tap(find.byTooltip('Fonts'));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.numpadEnter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.numpadEnter);
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
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'Menlo Custom',
      );

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'm');
      await tester.pump();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(find.text('Menlo')));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'Menlo',
      );

      await tester.tap(field);
      await tester.pump();
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
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

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
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
      await tester.testTextInput.receiveAction(TextInputAction.done);
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
      await tester.testTextInput.receiveAction(TextInputAction.done);
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
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<AleraTextField>(field).controller?.text, isEmpty);

      await tester.enterText(field, '#abcdef');
      await tester.testTextInput.receiveAction(TextInputAction.done);
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

  testWidgets('remote host bootstrap saves edited connection before start', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-1',
        alias: 'Laptop',
        host: 'old.example.com',
        username: 'old-user',
      ),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
      extraOverrides: <dynamic>[
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(runtimeClient),
        ),
      ],
    );
    await _selectRemoteHostsSection(tester);

    await _enterRemoteHostText(tester, 'Host', 'new.example.com');
    await _enterRemoteHostText(tester, 'Username', 'new-user');
    await _enterRemoteHostText(tester, 'Port', '2222');
    final bootstrapButton = find.widgetWithText(OutlinedButton, 'Bootstrap');
    await tester.ensureVisible(bootstrapButton);
    await tester.pumpAndSettle();
    await tester.tap(bootstrapButton);
    await tester.pumpAndSettle();

    final upsert = runtimeClient.requests.singleWhere(
      (request) => request.type == 'sshTarget.upsert',
    );
    final start = runtimeClient.requests.singleWhere(
      (request) => request.type == 'sshTarget.bootstrap.start',
    );
    expect(upsert.payload['host'], 'new.example.com');
    expect(upsert.payload['username'], 'new-user');
    expect(upsert.payload['port'], 2222);
    expect(start.payload['targetId'], 'ssh-1');
    expect(runtimeClient.targets.single.host, 'new.example.com');
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Plan'))
          .onPressed,
      isNull,
    );
    expect(tester.widget<OutlinedButton>(bootstrapButton).onPressed, isNull);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Remove'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<TextField>(_remoteHostTextField('Host')).enabled,
      isFalse,
    );
  });

  testWidgets('remote host bootstrap completion ignores stale selection', (
    tester,
  ) async {
    final bootstrapGate = Completer<void>();
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-first',
        alias: 'First Host',
        host: 'first.example.com',
      ),
      _sshTarget(
        id: 'ssh-second',
        alias: 'Second Host',
        host: 'second.example.com',
      ),
    ], bootstrapStartGate: bootstrapGate);
    addTearDown(runtimeClient.dispose);
    await _pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
      extraOverrides: <dynamic>[
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(runtimeClient),
        ),
      ],
    );
    await _selectRemoteHostsSection(tester);

    final bootstrapButton = find.widgetWithText(OutlinedButton, 'Bootstrap');
    await tester.ensureVisible(bootstrapButton);
    await tester.pumpAndSettle();
    await tester.tap(bootstrapButton);
    await tester.pump();

    await _pumpUntilRuntimeRequest(
      tester,
      runtimeClient,
      'sshTarget.bootstrap.start',
    );

    await _selectRemoteHost(tester, 'Second Host');

    bootstrapGate.complete();
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_remoteHostTextField('Host')).controller?.text,
      'second.example.com',
    );
    final cancelButton = find.widgetWithText(OutlinedButton, 'Cancel');
    await tester.ensureVisible(cancelButton);
    expect(tester.widget<OutlinedButton>(cancelButton).onPressed, isNull);
    expect(find.text('Remote Runtime Install Started'), findsNothing);
  });

  testWidgets('remote host plan completion ignores stale selection', (
    tester,
  ) async {
    final planGate = Completer<void>();
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-first',
        alias: 'First Host',
        host: 'first.example.com',
      ),
      _sshTarget(
        id: 'ssh-second',
        alias: 'Second Host',
        host: 'second.example.com',
      ),
    ], bootstrapPlanGate: planGate);
    addTearDown(runtimeClient.dispose);
    await _pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
      extraOverrides: <dynamic>[
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(runtimeClient),
        ),
      ],
    );
    await _selectRemoteHostsSection(tester);

    final planButton = find.widgetWithText(OutlinedButton, 'Plan');
    await tester.ensureVisible(planButton);
    await tester.pumpAndSettle();
    await tester.tap(planButton);
    await tester.pump();

    await _pumpUntilRuntimeRequest(
      tester,
      runtimeClient,
      'sshTarget.bootstrap.plan',
    );

    await _selectRemoteHost(tester, 'Second Host');

    planGate.complete();
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_remoteHostTextField('Host')).controller?.text,
      'second.example.com',
    );
    expect(find.text('Bootstrap Plan'), findsNothing);
    await tester.ensureVisible(planButton);
    expect(tester.widget<OutlinedButton>(planButton).onPressed, isNotNull);
  });

  testWidgets('remote host cancel completion ignores stale selection', (
    tester,
  ) async {
    final cancelGate = Completer<void>();
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-first',
        alias: 'First Host',
        host: 'first.example.com',
        bootstrapStatus: SshBootstrapStatus.installing,
      ),
      _sshTarget(
        id: 'ssh-second',
        alias: 'Second Host',
        host: 'second.example.com',
        bootstrapStatus: SshBootstrapStatus.installing,
      ),
    ], bootstrapCancelGate: cancelGate);
    addTearDown(runtimeClient.dispose);
    await _pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
      extraOverrides: <dynamic>[
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(runtimeClient),
        ),
      ],
    );
    await _selectRemoteHostsSection(tester);

    final cancelButton = find.widgetWithText(OutlinedButton, 'Cancel');
    await tester.ensureVisible(cancelButton);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(cancelButton).onPressed, isNotNull);
    await tester.tap(cancelButton);
    await tester.pump();

    await _pumpUntilRuntimeRequest(
      tester,
      runtimeClient,
      'sshTarget.bootstrap.cancel',
    );

    await _selectRemoteHost(tester, 'Second Host');

    cancelGate.complete();
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_remoteHostTextField('Host')).controller?.text,
      'second.example.com',
    );
    await tester.ensureVisible(cancelButton);
    expect(tester.widget<OutlinedButton>(cancelButton).onPressed, isNotNull);
    expect(find.text('Remote Runtime Error'), findsNothing);
  });

  testWidgets('remote host external delete selects remaining target', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-first',
        alias: 'First Host',
        host: 'first.example.com',
      ),
      _sshTarget(
        id: 'ssh-second',
        alias: 'Second Host',
        host: 'second.example.com',
      ),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
      extraOverrides: <dynamic>[
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(runtimeClient),
        ),
      ],
    );
    await _selectRemoteHostsSection(tester);

    runtimeClient.targets.removeWhere((target) => target.id == 'ssh-first');
    runtimeClient.emitSshTargetsChanged();
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_remoteHostTextField('Host')).controller?.text,
      'second.example.com',
    );

    await _enterRemoteHostText(tester, 'Host', 'second-edited.example.com');
    final saveButton = find.widgetWithText(ElevatedButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final upsert = runtimeClient.requests.lastWhere(
      (request) => request.type == 'sshTarget.upsert',
    );
    expect(upsert.payload['id'], 'ssh-second');
    expect(upsert.payload['host'], 'second-edited.example.com');
    expect(
      runtimeClient.requests.where(
        (request) =>
            request.type == 'sshTarget.upsert' &&
            request.payload['id'] == 'ssh-first',
      ),
      isEmpty,
    );
  });

  testWidgets('remote host pane shows persisted bootstrap failure details', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-failed',
        alias: 'Failed Host',
        host: 'failed.example.com',
        bootstrapStatus: SshBootstrapStatus.failed,
        lastError: 'Permission denied while installing runtime',
      ),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
      extraOverrides: <dynamic>[
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(runtimeClient),
        ),
      ],
    );
    await _selectRemoteHostsSection(tester);

    expect(find.text('Failed'), findsOneWidget);
    expect(
      find.text('Permission denied while installing runtime'),
      findsOneWidget,
    );
  });

  testWidgets('remote host save preserves password auth targets', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-password',
        alias: 'Password Host',
        host: 'password.example.com',
        authKind: SshAuthKind.password,
      ),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
      extraOverrides: <dynamic>[
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(runtimeClient),
        ),
      ],
    );
    await _selectRemoteHostsSection(tester);

    expect(find.text('Password'), findsOneWidget);

    final saveButton = find.widgetWithText(ElevatedButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final upsert = runtimeClient.requests.singleWhere(
      (request) => request.type == 'sshTarget.upsert',
    );
    expect(upsert.payload['authKind'], 'password');
  });

  testWidgets('remote host rejects invalid port input', (tester) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(id: 'ssh-port', alias: 'Port Host', host: 'port.example.com'),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
      extraOverrides: <dynamic>[
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(runtimeClient),
        ),
      ],
    );
    await _selectRemoteHostsSection(tester);

    await _enterRemoteHostText(tester, 'Port', '2222a');
    final saveButton = find.widgetWithText(ElevatedButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Port Must Be Between 1 And 65535'), findsOneWidget);
    expect(
      runtimeClient.requests.where(
        (request) => request.type == 'sshTarget.upsert',
      ),
      isEmpty,
    );

    await _enterRemoteHostText(tester, 'Port', '70000');
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Port Must Be Between 1 And 65535'), findsOneWidget);
    expect(
      runtimeClient.requests.where(
        (request) => request.type == 'sshTarget.upsert',
      ),
      isEmpty,
    );
  });

  testWidgets('remote host status refresh preserves unsaved connection edits', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-refresh',
        alias: 'Refreshing Host',
        host: 'old.example.com',
        username: 'old-user',
      ),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
      extraOverrides: <dynamic>[
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(runtimeClient),
        ),
      ],
    );
    await _selectRemoteHostsSection(tester);

    await _enterRemoteHostText(tester, 'Host', 'unsaved.example.com');
    runtimeClient.targets[0] = _sshTarget(
      id: 'ssh-refresh',
      alias: 'Refreshing Host',
      host: 'old.example.com',
      username: 'old-user',
      bootstrapStatus: SshBootstrapStatus.installed,
    );
    runtimeClient.emitSshTargetsChanged();
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_remoteHostTextField('Host')).controller?.text,
      'unsaved.example.com',
    );
    expect(find.text('Installed'), findsWidgets);
  });

  testWidgets('remote host dropdowns reseed when selection changes', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-mac',
        alias: 'Mac Host',
        host: 'mac.example.com',
        platform: 'Darwin',
        arch: 'x86_64',
      ),
      _sshTarget(
        id: 'ssh-linux',
        alias: 'Linux Host',
        host: 'linux.example.com',
        platform: 'linux',
        arch: 'arm64',
      ),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(GitHubStarState.hidden),
      extraOverrides: <dynamic>[
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(runtimeClient),
        ),
      ],
    );
    await _selectRemoteHostsSection(tester);

    expect(
      find.byKey(const ValueKey<String>('Platform:macos')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('Architecture:x64')),
      findsOneWidget,
    );

    await tester.tap(find.text('Linux Host').first);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('Platform:linux')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('Architecture:arm64')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('New Host'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('Architecture:')));
    await tester.pumpAndSettle();

    expect(find.text('x64'), findsWidgets);
    expect(find.text('arm64'), findsWidgets);
  });
}

Future<void> _pumpUntilRuntimeRequest(
  WidgetTester tester,
  _FakeRuntimeHostClient runtimeClient,
  String type,
) async {
  for (var attempt = 0; attempt < 10; attempt += 1) {
    if (runtimeClient.requests.any((request) => request.type == type)) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(runtimeClient.requests.any((request) => request.type == type), isTrue);
}

Future<void> _selectRemoteHost(WidgetTester tester, String alias) async {
  final row = find
      .ancestor(of: find.text(alias), matching: find.byType(InkWell))
      .first;
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _selectRemoteHostsSection(WidgetTester tester) async {
  await tester.tap(find.text('Remote Hosts').first);
  await tester.pumpAndSettle();
}

Future<void> _enterRemoteHostText(
  WidgetTester tester,
  String label,
  String value,
) async {
  final field = _remoteHostTextField(label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Finder _remoteHostTextField(String label) {
  return find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is AleraTextField && widget.labelText == label,
    ),
    matching: find.byType(TextField),
  );
}

SshTarget _sshTarget({
  required String id,
  required String alias,
  required String host,
  String username = 'alera',
  String? platform,
  String? arch,
  SshAuthKind authKind = SshAuthKind.agent,
  SshBootstrapStatus bootstrapStatus = SshBootstrapStatus.notInstalled,
  String? lastError,
}) {
  final now = DateTime.utc(2026, 6, 27);
  return SshTarget(
    id: id,
    alias: alias,
    host: host,
    port: 22,
    username: username,
    platform: platform,
    arch: arch,
    authKind: authKind,
    createdAt: now,
    updatedAt: now,
    bootstrapStatus: bootstrapStatus,
    lastError: lastError,
  );
}
