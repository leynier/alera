part of 'settings_dialog_test.dart';

void _registerSettingsDialogRemoteHostTests() {
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
}

Future<void> _pumpRemoteHostsPane(
  WidgetTester tester,
  _FakeRuntimeHostClient runtimeClient,
) async {
  await _pumpSettingsDialog(
    tester,
    starController: _FakeGitHubStarController(.hidden),
    extraOverrides: <dynamic>[
      sshTargetRepositoryProvider.overrideWithValue(
        RuntimeSshTargetRepository(
          runtimeClient,
          coalescer: _immediateCoalescer(),
        ),
      ),
    ],
  );
  await _selectRemoteHostsSection(tester);
}

Future<void> _tapRemoteHostSave(WidgetTester tester) async {
  final saveButton = find.widgetWithText(FilledButton, 'Save');
  await tester.ensureVisible(saveButton);
  await tester.pumpAndSettle();
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
}
