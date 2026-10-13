import 'dart:async';

import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/remote_project_request.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/presentation/add_project_to_host_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/remote_hosts_widget_harness.dart';

void main() {
  testWidgets('the header names the host and its state', (tester) async {
    await _pumpDialog(tester, _Recorder());

    expect(find.text('Add Project to Build Mac'), findsOneWidget);
    expect(
      tester.widget<AleraBadge>(find.byType(AleraBadge)).label,
      'Connected',
    );
    expect(find.text('Existing Project'), findsOneWidget);
    expect(find.text('New Remote Project'), findsOneWidget);
  });

  testWidgets('adds an existing project to the host and closes', (
    tester,
  ) async {
    final recorder = _Recorder()..gate = Completer<void>();
    await _pumpDialog(tester, recorder);

    // Already on the host, and a folder project, are not offered.
    await tester.tap(find.text('Select Project'));
    await tester.pumpAndSettle();
    expect(find.text('Web'), findsOneWidget);
    expect(find.text('Api'), findsNothing);
    expect(find.text('Notes'), findsNothing);
    await tester.tap(find.text('Web').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Existing Path'),
      '/srv/web',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add to Host'));
    await tester.pump();
    expect(
      find.text(
        'Adding the project to the host. A clone can take a few minutes.',
      ),
      findsOneWidget,
    );

    recorder.gate!.complete();
    await tester.pumpAndSettle();

    expect(recorder.added, <(String, String, String?)>[
      ('web', 'ssh-mac', '/srv/web'),
    ]);
    expect(recorder.result?.id, 'web');
    expect(find.text('Add Project to Build Mac'), findsNothing);
  });

  testWidgets('a failed add stays open with the runtime message', (
    tester,
  ) async {
    final recorder = _Recorder()
      ..addError = StateError('The project has no Git remote to clone.');
    await _pumpDialog(tester, recorder);

    await tester.tap(find.text('Select Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Web').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add to Host'));
    await tester.pumpAndSettle();

    expect(
      find.text('The project has no Git remote to clone.'),
      findsOneWidget,
    );
    expect(recorder.added.single.$3, isNull);
    expect(find.text('Add Project to Build Mac'), findsOneWidget);
  });

  testWidgets('registers a new remote project on the fixed host', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pumpDialog(
      tester,
      recorder,
      initialMode: AddProjectToHostMode.newRemoteProject,
    );

    // The host is fixed, so there is no picker.
    expect(find.text('Select Host'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Add Project'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Add Project'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Clone Repository'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Git URL'),
      'git@github.com:o/cli.git',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Project'));
    await tester.pumpAndSettle();

    final request = recorder.registered.single;
    expect(request.hostId, 'ssh-mac');
    expect(request.cloneUrl, 'git@github.com:o/cli.git');
    expect(request.path, isNull);
    expect(recorder.result?.id, 'remote-project');
    expect(find.text('Add Project to Build Mac'), findsNothing);
  });

  testWidgets('with nothing to add it opens on New Remote Project', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      _Recorder(),
      projects: <Project>[
        remoteHostTestProject(
          'api',
          'Api',
          checkouts: const <ProjectCheckout>[
            ProjectCheckout(hostId: 'ssh-mac', path: '/srv/api'),
          ],
        ),
      ],
    );

    expect(find.text('Folder on the Host'), findsOneWidget);
    expect(find.text('Select Project'), findsNothing);

    await tester.tap(find.text('Existing Project'));
    await tester.pumpAndSettle();
    final notice = tester.widget<AleraInlineNotice>(
      find.byType(AleraInlineNotice),
    );
    expect(notice.tone, AleraInlineNoticeTone.info);
    expect(
      notice.message,
      'Every Git project is already on Build Mac. Create a new remote project instead.',
    );
    expect(find.widgetWithText(FilledButton, 'Add Project'), findsNothing);
  });

  testWidgets('a host that is not ready offers no form', (tester) async {
    await _pumpDialog(
      tester,
      _Recorder(),
      status: const RemoteHostNeedsSetup(),
    );

    expect(
      find.textContaining('Projects can be added once Build Mac is ready.'),
      findsOneWidget,
    );
    expect(find.text('Existing Project'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Add Project'), findsNothing);
  });
}

class _Recorder {
  final List<(String, String, String?)> added = <(String, String, String?)>[];
  final List<RemoteProjectRequest> registered = <RemoteProjectRequest>[];
  Completer<void>? gate;
  Object? addError;
  Project? result;

  Future<Project> add(
    Project project,
    String hostId,
    String? existingPath,
  ) async {
    added.add((project.id, hostId, existingPath));
    await gate?.future;
    if (addError case final error?) {
      throw error;
    }
    return project;
  }

  Future<Project> register(RemoteProjectRequest request) async {
    registered.add(request);
    return remoteHostTestProject(
      'remote-project',
      'Cli',
      primaryHostId: request.hostId,
    );
  }
}

Future<void> _pumpDialog(
  WidgetTester tester,
  _Recorder recorder, {
  AddProjectToHostMode initialMode = AddProjectToHostMode.existingProject,
  RemoteHostStatus status = const RemoteHostConnected(),
  List<Project>? projects,
}) async {
  final folder = Project(
    id: 'notes',
    name: 'Notes',
    repoPath: '/repos/notes',
    createdAt: DateTime.utc(2026, 10),
    updatedAt: DateTime.utc(2026, 10),
    kind: ProjectKind.folder,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              recorder.result = await showDialog<Project>(
                context: context,
                builder: (_) => AddProjectToHostDialog(
                  hostId: 'ssh-mac',
                  initialMode: initialMode,
                  hosts: <RemoteHostView>[
                    remoteHostTestView('ssh-mac', 'Build Mac', status: status),
                  ],
                  projects:
                      projects ??
                      <Project>[
                        remoteHostTestProject('web', 'Web'),
                        remoteHostTestProject(
                          'api',
                          'Api',
                          checkouts: const <ProjectCheckout>[
                            ProjectCheckout(
                              hostId: 'ssh-mac',
                              path: '/srv/api',
                            ),
                          ],
                        ),
                        folder,
                      ],
                  addProjectToHost: recorder.add,
                  registerRemoteProject: recorder.register,
                ),
              );
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
