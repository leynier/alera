part of 'settings_dialog_test.dart';

void _registerSettingsDialogRemoteHostTests() {
  testWidgets('remote hosts copy names the Alera runtime', (tester) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[]);
    addTearDown(runtimeClient.dispose);
    await _pumpRemoteHostsPane(tester, runtimeClient);

    expect(
      find.text(
        'Run workspaces on other machines over SSH. Alera installs and updates its runtime there.',
      ),
      findsOneWidget,
    );
    expect(find.text('No remote hosts'), findsOneWidget);
    expect(find.text(remoteHostsEmptyMessage), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add Host'), findsOneWidget);
    expect(find.textContaining('sidecar'), findsNothing);
  });

  testWidgets('remote host projects folder shows the target value', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-1',
        alias: 'Laptop',
        host: 'laptop.example.com',
      ).copyWith(projectsDir: r'%USERPROFILE%\code'),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpRemoteHostsPane(tester, runtimeClient);
    await _expandRemoteHostAdvanced(tester);

    expect(
      tester
          .widget<TextField>(_remoteHostTextField('Projects Folder'))
          .controller
          ?.text,
      r'%USERPROFILE%\code',
    );
    expect(find.text(projectsFolderHelpText), findsOneWidget);
  });

  testWidgets('remote host save sends the trimmed projects folder', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(id: 'ssh-1', alias: 'Laptop', host: 'laptop.example.com'),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpRemoteHostsPane(tester, runtimeClient);
    await _expandRemoteHostAdvanced(tester);

    await _enterRemoteHostText(tester, 'Projects Folder', '  ~/code  ');
    await _tapRemoteHostSave(tester);

    final upsert = runtimeClient.requests.singleWhere(
      (request) => request.type == 'sshTarget.upsert',
    );
    expect(upsert.payload['id'], 'ssh-1');
    expect(upsert.payload['projectsDir'], '~/code');
    expect(runtimeClient.targets.single.projectsDir, '~/code');
  });

  testWidgets('remote host save sends null for a blank projects folder', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-1',
        alias: 'Laptop',
        host: 'laptop.example.com',
      ).copyWith(projectsDir: '~/code'),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpRemoteHostsPane(tester, runtimeClient);
    await _expandRemoteHostAdvanced(tester);

    await _enterRemoteHostText(tester, 'Projects Folder', '   ');
    await _tapRemoteHostSave(tester);

    final upsert = runtimeClient.requests.singleWhere(
      (request) => request.type == 'sshTarget.upsert',
    );
    expect(upsert.payload.containsKey('projectsDir'), isTrue);
    expect(upsert.payload['projectsDir'], isNull);
    expect(runtimeClient.targets.single.projectsDir, isNull);
  });

  testWidgets('remote host projects folder reseeds on an external change', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(
        id: 'ssh-1',
        alias: 'Laptop',
        host: 'laptop.example.com',
      ).copyWith(projectsDir: '~/code'),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpRemoteHostsPane(tester, runtimeClient);
    await _expandRemoteHostAdvanced(tester);

    runtimeClient.targets[0] = runtimeClient.targets[0].copyWith(
      projectsDir: '/srv/projects',
    );
    runtimeClient.emitSshTargetsChanged();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(_remoteHostTextField('Projects Folder'))
          .controller
          ?.text,
      '/srv/projects',
    );
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
    await _pumpRemoteHostsPane(tester, runtimeClient);
    await _expandRemoteHostAdvanced(tester);

    expect(
      find.byKey(const ValueKey<String>('Platform:macos')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('Architecture:x64')),
      findsOneWidget,
    );

    await _selectRemoteHost(tester, 'Linux Host');
    await _expandRemoteHostAdvanced(tester);

    expect(
      find.byKey(const ValueKey<String>('Platform:linux')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('Architecture:arm64')),
      findsOneWidget,
    );
  });

  testWidgets('unsaved advanced settings ask before switching hosts', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(id: 'ssh-first', alias: 'First Host', host: 'first.example'),
      _sshTarget(
        id: 'ssh-second',
        alias: 'Second Host',
        host: 'second.example',
      ),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpRemoteHostsPane(tester, runtimeClient);
    await _expandRemoteHostAdvanced(tester);
    await _enterRemoteHostText(tester, 'Projects Folder', '~/work');

    await _selectRemoteHost(tester, 'Second Host');
    expect(find.text('Save Changes?'), findsOneWidget);
    expect(
      find.text('First Host has unsaved advanced settings.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Keep Editing'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(_remoteHostTextField('Projects Folder'))
          .controller
          ?.text,
      '~/work',
    );

    await _selectRemoteHost(tester, 'Second Host');
    // The dialog's Save sits above the Advanced group's own Save button.
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final upsert = runtimeClient.requests.singleWhere(
      (request) => request.type == 'sshTarget.upsert',
    );
    expect(upsert.payload['id'], 'ssh-first');
    expect(upsert.payload['projectsDir'], '~/work');
    expect(find.text('second.example'), findsNothing);
    expect(find.textContaining('alera@second.example'), findsWidgets);
  });

  testWidgets('remote hosts deep link opens the requested host', (
    tester,
  ) async {
    final runtimeClient = _FakeRuntimeHostClient(<SshTarget>[
      _sshTarget(id: 'ssh-first', alias: 'First Host', host: 'first.example'),
      _sshTarget(
        id: 'ssh-second',
        alias: 'Second Host',
        host: 'second.example',
      ),
    ]);
    addTearDown(runtimeClient.dispose);
    await _pumpSettingsDialog(
      tester,
      starController: _FakeGitHubStarController(.hidden),
      initialSectionId: 'remoteHosts',
      initialHostId: 'ssh-second',
      extraOverrides: _remoteHostOverrides(runtimeClient),
    );
    await tester.pumpAndSettle();

    final header = find.byType(RemoteHostHeaderCard);
    expect(
      find.descendant(of: header, matching: find.text('Second Host')),
      findsOneWidget,
    );
  });
}

List<dynamic> _remoteHostOverrides(_FakeRuntimeHostClient runtimeClient) {
  return <dynamic>[
    sshTargetRepositoryProvider.overrideWithValue(
      RuntimeSshTargetRepository(
        runtimeClient,
        coalescer: _immediateCoalescer(),
      ),
    ),
    projectListProvider.overrideWithValue(const AsyncData<List<Project>>([])),
    projectHostsSupportedProvider.overrideWithValue(const AsyncData(false)),
  ];
}

Future<void> _pumpRemoteHostsPane(
  WidgetTester tester,
  _FakeRuntimeHostClient runtimeClient,
) async {
  await _pumpSettingsDialog(
    tester,
    starController: _FakeGitHubStarController(.hidden),
    extraOverrides: _remoteHostOverrides(runtimeClient),
  );
  await tester.tap(find.text('Remote Hosts').first);
  await tester.pumpAndSettle();
}

Future<void> _expandRemoteHostAdvanced(WidgetTester tester) async {
  final heading = find.text('Advanced');
  await tester.ensureVisible(heading);
  await tester.pumpAndSettle();
  await tester.tap(heading);
  await tester.pumpAndSettle();
}

Future<void> _tapRemoteHostSave(WidgetTester tester) async {
  final saveButton = find.widgetWithText(FilledButton, 'Save');
  await tester.ensureVisible(saveButton);
  await tester.pumpAndSettle();
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
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
