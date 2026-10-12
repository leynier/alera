import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/remote_project_request.dart';
import 'package:alera/src/features/projects/presentation/add_remote_project_dialog.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/remote_hosts_widget_harness.dart';

final DateTime _now = DateTime.utc(2026, 9, 21);

void main() {
  testWidgets('lists hosts that are not ready with the reason, unpickable', (
    tester,
  ) async {
    await _pumpDialog(tester, _FakeRegistration());

    expect(find.text('Add Remote Project'), findsOneWidget);
    expect(find.text('Select Host'), findsOneWidget);
    await tester.tap(find.text('Select Host'));
    await tester.pumpAndSettle();

    expect(find.text('Build Mac'), findsOneWidget);
    expect(find.text('Build PC'), findsOneWidget);
    expect(find.text('Staging (Needs Setup)'), findsOneWidget);
    expect(
      tester
          .widgetList<AleraHostOsIcon>(find.byType(AleraHostOsIcon))
          .map((icon) => icon.os),
      containsAll(<HostOs>[HostOs.macos, HostOs.windows]),
    );

    // A disabled entry does not pick the host; the menu stays open.
    await tester.tap(find.text('Staging (Needs Setup)'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Staging (Needs Setup)'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Select Host'), findsOneWidget);
  });

  testWidgets('with no ready host it offers Add Host instead of the form', (
    tester,
  ) async {
    var addHost = 0;
    await _pumpDialog(
      tester,
      _FakeRegistration(),
      hosts: <RemoteHostView>[
        remoteHostTestView(
          'ssh-staging',
          'Staging',
          status: const RemoteHostNeedsSetup(),
        ),
      ],
      onAddHost: () => addHost++,
    );

    expect(find.text('No host is ready'), findsOneWidget);
    expect(
      find.text(
        'Install the Alera runtime on a host before adding projects there.',
      ),
      findsOneWidget,
    );
    expect(find.text('Folder on the Host'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Add Project'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Add Host'));
    await tester.pump();
    expect(addHost, 1);
  });

  testWidgets('a single ready host is selected up front', (tester) async {
    await _pumpDialog(
      tester,
      _FakeRegistration(),
      hosts: <RemoteHostView>[
        remoteHostTestView('ssh-mac', 'Build Mac'),
        remoteHostTestView(
          'ssh-staging',
          'Staging',
          status: const RemoteHostNeedsSetup(),
        ),
      ],
    );

    expect(find.text('Build Mac'), findsOneWidget);
    expect(find.text('Select Host'), findsNothing);
  });

  testWidgets('Add Project stays disabled until the required fields are set', (
    tester,
  ) async {
    final registration = _FakeRegistration();
    await _pumpDialog(tester, registration);

    expect(_addButton(tester).onPressed, isNull);

    await tester.enterText(_field('Folder on the Host'), '/srv/api');
    await tester.pump();
    // Still no host.
    expect(_addButton(tester).onPressed, isNull);

    await _selectHost(tester, 'Build Mac');
    expect(_addButton(tester).onPressed, isNotNull);

    await tester.enterText(_field('Folder on the Host'), '   ');
    await tester.pump();
    expect(_addButton(tester).onPressed, isNull);

    // The folder never stands in for the clone URL.
    await tester.enterText(_field('Folder on the Host'), '/srv/api');
    await tester.tap(find.text('Clone Repository'));
    await tester.pumpAndSettle();
    expect(_addButton(tester).onPressed, isNull);
    expect(find.text('Git Repository'), findsNothing);

    await tester.testTextInput.receiveAction(.done);
    await tester.pump();
    expect(registration.requests, isEmpty);
  });

  testWidgets('registers an existing folder with its kind and name', (
    tester,
  ) async {
    final registration = _FakeRegistration();
    Project? result;
    await _pumpDialog(
      tester,
      registration,
      onResult: (value) => result = value,
    );

    await _selectHost(tester, 'Build PC');
    expect(
      tester
          .widget<TextField>(_field('Folder on the Host'))
          .decoration
          ?.hintText,
      r'C:\Users\me\project',
    );
    await tester.enterText(_field('Folder on the Host'), r' C:\work\notes ');
    await tester.enterText(_field('Display Name (Optional)'), ' Notes ');
    await tester.tap(find.text('Folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Project'));
    await tester.pumpAndSettle();

    final request = registration.requests.single;
    expect(request.hostId, 'ssh-win');
    expect(request.path, r'C:\work\notes');
    expect(request.cloneUrl, isNull);
    expect(request.name, 'Notes');
    expect(request.kind, ProjectKind.folder);
    expect(result?.id, 'project-remote');
    expect(find.text('Add Remote Project'), findsNothing);
  });

  testWidgets('shows progress in place and closes when the clone succeeds', (
    tester,
  ) async {
    final registration = _FakeRegistration()..completer = Completer<Project>();
    Project? result;
    await _pumpDialog(
      tester,
      registration,
      onResult: (value) => result = value,
    );

    await _selectHost(tester, 'Build Mac');
    await tester.tap(find.text('Clone Repository'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Git URL'), 'git@github.com:o/api.git');
    await tester.pump();
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.textContaining('A clone can take a few minutes'),
      findsOneWidget,
    );
    expect(_addButton(tester).onPressed, isNull);
    expect(tester.widget<TextField>(_field('Git URL')).enabled, isFalse);
    expect(registration.requests.single.cloneUrl, 'git@github.com:o/api.git');
    expect(registration.requests.single.kind, ProjectKind.gitRepository);

    registration.completer!.complete(_project());
    await tester.pumpAndSettle();

    expect(result?.id, 'project-remote');
    expect(find.text('Add Remote Project'), findsNothing);
  });

  testWidgets('shows the runtime error inline and lets the user retry', (
    tester,
  ) async {
    final registration = _FakeRegistration()
      ..error = StateError(
        'This folder is already the project "Api" on that host',
      );
    await _pumpDialog(tester, registration);

    await _selectHost(tester, 'Build Mac');
    await tester.enterText(_field('Folder on the Host'), '/srv/api');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Project'));
    await tester.pumpAndSettle();

    final notice = tester.widget<AleraInlineNotice>(
      find.byType(AleraInlineNotice),
    );
    expect(notice.tone, AleraInlineNoticeTone.error);
    expect(
      notice.message,
      'This folder is already the project "Api" on that host',
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Add Remote Project'), findsOneWidget);

    await tester.enterText(_field('Folder on the Host'), '/srv/other');
    await tester.pump();
    expect(find.byType(AleraInlineNotice), findsNothing);

    registration.error = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Add Project'));
    await tester.pumpAndSettle();
    expect(registration.requests, hasLength(2));
    expect(find.text('Add Remote Project'), findsNothing);
  });

  testWidgets('Cancel closes the dialog while the request is running', (
    tester,
  ) async {
    final registration = _FakeRegistration()..completer = Completer<Project>();
    var results = 0;
    Project? result;
    await _pumpDialog(
      tester,
      registration,
      onResult: (value) {
        results += 1;
        result = value;
      },
    );

    await _selectHost(tester, 'Build Mac');
    await tester.enterText(_field('Folder on the Host'), '/srv/api');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Project'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Add Remote Project'), findsNothing);
    expect(results, 1);
    expect(result, isNull);

    // The request outlives the dialog; finishing it must not touch the
    // disposed form.
    registration.completer!.complete(_project());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Finder _field(String label) => find.widgetWithText(TextField, label);

FilledButton _addButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Add Project'),
  );
}

Future<void> _selectHost(WidgetTester tester, String alias) async {
  await tester.tap(find.text('Select Host'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(alias).last);
  await tester.pumpAndSettle();
}

class _FakeRegistration {
  final List<RemoteProjectRequest> requests = <RemoteProjectRequest>[];
  Completer<Project>? completer;
  Object? error;

  Future<Project> call(RemoteProjectRequest request) async {
    requests.add(request);
    if (error case final error?) {
      throw error;
    }
    return completer?.future ?? _project();
  }
}

Future<void> _pumpDialog(
  WidgetTester tester,
  _FakeRegistration registration, {
  List<RemoteHostView>? hosts,
  ValueChanged<Project?>? onResult,
  VoidCallback? onAddHost,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              final result = await showDialog<Project>(
                context: context,
                builder: (_) => AddRemoteProjectDialog(
                  hosts:
                      hosts ??
                      <RemoteHostView>[
                        remoteHostTestView('ssh-mac', 'Build Mac'),
                        remoteHostTestView(
                          'ssh-win',
                          'Build PC',
                          os: HostOs.windows,
                        ),
                        remoteHostTestView(
                          'ssh-staging',
                          'Staging',
                          status: const RemoteHostNeedsSetup(),
                        ),
                      ],
                  registerRemoteProject: registration.call,
                  onAddHost: onAddHost,
                ),
              );
              onResult?.call(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Project _project() {
  return Project(
    id: 'project-remote',
    name: 'Api',
    repoPath: '/srv/api',
    createdAt: _now,
    updatedAt: _now,
    primaryHostId: 'ssh-mac',
  );
}
