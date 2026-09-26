import 'dart:async';

import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/infra/runtime_project_hosts_client.dart';
import 'package:alera/src/features/projects/presentation/project_host_row.dart';
import 'package:alera/src/features/projects/presentation/project_hosts_dialog.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 9, 21);

void main() {
  testWidgets('lists each host with its path, workspaces and primary marker', (
    tester,
  ) async {
    final runtime = _FakeProjectHosts(<ProjectHost>[
      const ProjectHost(
        hostId: 'local',
        path: '/repo/alera',
        primary: true,
        workspaceCount: 3,
      ),
      const ProjectHost(
        hostId: 'ssh-mac',
        path: '/Users/me/alera-projects/alera',
        primary: false,
        workspaceCount: 1,
      ),
      const ProjectHost(
        hostId: 'ssh-win',
        path: r'C:\Users\me\alera-projects\alera',
        primary: false,
        workspaceCount: 0,
      ),
    ]);
    await _pumpDialog(tester, runtime);

    expect(find.text('Alera Hosts'), findsOneWidget);
    expect(find.text('This Device'), findsOneWidget);
    expect(find.text('Build Mac'), findsOneWidget);
    expect(find.text('Build PC'), findsOneWidget);
    expect(find.text('/Users/me/alera-projects/alera'), findsOneWidget);
    expect(find.text('3 workspaces'), findsOneWidget);
    expect(find.text('1 workspace'), findsOneWidget);
    expect(find.text('No workspaces'), findsOneWidget);
    expect(find.text('Primary'), findsOneWidget);
    expect(
      tester
          .widget<AleraHostOsIcon>(
            find.descendant(
              of: find.widgetWithText(ProjectHostRow, 'Build Mac'),
              matching: find.byType(AleraHostOsIcon),
            ),
          )
          .os,
      HostOs.macos,
    );

    expect(
      _removeButton(tester, 'This Device').tooltip,
      "The primary host holds the project's main folder.",
    );
    expect(_removeButton(tester, 'This Device').onPressed, isNull);
    expect(
      _removeButton(tester, 'Build Mac').tooltip,
      'Remove the workspaces on this host first.',
    );
    expect(_removeButton(tester, 'Build Mac').onPressed, isNull);
    expect(_removeButton(tester, 'Build PC').tooltip, 'Remove From Host');
    expect(_removeButton(tester, 'Build PC').onPressed, isNotNull);
  });

  testWidgets('the only host cannot be removed', (tester) async {
    final runtime = _FakeProjectHosts(<ProjectHost>[
      const ProjectHost(
        hostId: 'local',
        path: '/repo/alera',
        primary: true,
        workspaceCount: 0,
      ),
    ]);
    await _pumpDialog(tester, runtime);

    expect(
      _removeButton(tester, 'This Device').tooltip,
      "This is the project's only host.",
    );
    expect(_removeButton(tester, 'This Device').onPressed, isNull);
  });

  testWidgets('removes an idle host after confirming', (tester) async {
    final runtime = _FakeProjectHosts(<ProjectHost>[
      const ProjectHost(
        hostId: 'local',
        path: '/repo/alera',
        primary: true,
        workspaceCount: 0,
      ),
      const ProjectHost(
        hostId: 'ssh-win',
        path: r'C:\alera',
        primary: false,
        workspaceCount: 0,
      ),
    ]);
    await _pumpDialog(tester, runtime);

    await tester.tap(find.byTooltip('Remove From Host'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Alera will no longer be on Build PC. Files on the host are not deleted.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(runtime.removed, <String>['ssh-win']);
    expect(find.widgetWithText(ProjectHostRow, 'Build PC'), findsNothing);
  });

  testWidgets('a refused removal shows the runtime message', (tester) async {
    final runtime = _FakeProjectHosts(<ProjectHost>[
      const ProjectHost(
        hostId: 'local',
        path: '/repo/alera',
        primary: true,
        workspaceCount: 0,
      ),
      const ProjectHost(
        hostId: 'ssh-win',
        path: r'C:\alera',
        primary: false,
        workspaceCount: 0,
      ),
    ])..removeError = StateError('Workspaces still exist on this host.');
    await _pumpDialog(tester, runtime);

    await tester.tap(find.byTooltip('Remove From Host'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Workspaces still exist on this host.'), findsOneWidget);
    expect(find.widgetWithText(ProjectHostRow, 'Build PC'), findsOneWidget);
  });

  testWidgets('adds the project to a bootstrapped host it is not on', (
    tester,
  ) async {
    final runtime = _FakeProjectHosts(<ProjectHost>[
      const ProjectHost(
        hostId: 'local',
        path: '/repo/alera',
        primary: true,
        workspaceCount: 0,
      ),
      const ProjectHost(
        hostId: 'ssh-mac',
        path: '/Users/me/alera',
        primary: false,
        workspaceCount: 0,
      ),
    ])..gate = Completer<void>();
    await _pumpDialog(tester, runtime);

    expect(_addButton(tester).onPressed, isNull);
    await tester.tap(find.text('Select Host'));
    await tester.pumpAndSettle();
    // Build Mac already has the project and Staging is not bootstrapped.
    expect(find.text('Build Mac'), findsOneWidget);
    expect(find.textContaining('Staging'), findsNothing);
    await tester.tap(find.text('Build PC').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Existing Path'),
      r'D:\src\alera',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add to Host'));
    await tester.pump();

    expect(
      find.text(
        'Adding the project to the host. A clone can take a few minutes.',
      ),
      findsOneWidget,
    );

    runtime.gate!.complete();
    await tester.pumpAndSettle();

    expect(runtime.added, <(String, String?)>[('ssh-win', r'D:\src\alera')]);
    expect(find.widgetWithText(ProjectHostRow, 'Build PC'), findsOneWidget);
    expect(find.text(r'D:\src\alera'), findsOneWidget);
    expect(
      find.textContaining('already on every bootstrapped host'),
      findsOneWidget,
    );
  });

  testWidgets('a failed add shows the runtime message', (tester) async {
    final runtime = _FakeProjectHosts(<ProjectHost>[
      const ProjectHost(
        hostId: 'local',
        path: '/repo/alera',
        primary: true,
        workspaceCount: 0,
      ),
    ])..addError = StateError('The project has no Git remote to clone.');
    await _pumpDialog(tester, runtime);

    await tester.tap(find.text('Select Host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Mac'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add to Host'));
    await tester.pumpAndSettle();

    expect(
      find.text('The project has no Git remote to clone.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ProjectHostRow, 'Build Mac'), findsNothing);
  });

  testWidgets('a failed load can be retried', (tester) async {
    final runtime = _FakeProjectHosts(<ProjectHost>[
      const ProjectHost(
        hostId: 'local',
        path: '/repo/alera',
        primary: true,
        workspaceCount: 0,
      ),
    ])..loadError = StateError('The runtime is not reachable.');
    await _pumpDialog(tester, runtime);

    expect(find.text('The runtime is not reachable.'), findsOneWidget);
    runtime.loadError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('This Device'), findsOneWidget);
  });
}

AleraIconButton _removeButton(WidgetTester tester, String hostLabel) {
  return tester.widget<AleraIconButton>(
    find.descendant(
      of: find.widgetWithText(ProjectHostRow, hostLabel),
      matching: find.byType(AleraIconButton),
    ),
  );
}

FilledButton _addButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Add to Host'),
  );
}

class _FakeProjectHosts {
  _FakeProjectHosts(this.hosts);

  List<ProjectHost> hosts;
  final List<(String, String?)> added = <(String, String?)>[];
  final List<String> removed = <String>[];
  Completer<void>? gate;
  Object? loadError;
  Object? addError;
  Object? removeError;

  Future<List<ProjectHost>> list() async {
    if (loadError case final error?) {
      throw error;
    }
    return hosts;
  }

  Future<Project> add(
    Project project,
    String hostId,
    String? existingPath,
  ) async {
    added.add((hostId, existingPath));
    await gate?.future;
    if (addError case final error?) {
      throw error;
    }
    hosts = <ProjectHost>[
      ...hosts,
      ProjectHost(
        hostId: hostId,
        path: existingPath ?? '/cloned',
        primary: false,
        workspaceCount: 0,
      ),
    ];
    return project;
  }

  Future<List<ProjectHost>> remove(String hostId) async {
    if (removeError case final error?) {
      throw error;
    }
    removed.add(hostId);
    hosts = <ProjectHost>[
      for (final host in hosts)
        if (host.hostId != hostId) host,
    ];
    return hosts;
  }
}

Future<void> _pumpDialog(WidgetTester tester, _FakeProjectHosts runtime) async {
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: _now,
    updatedAt: _now,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ProjectHostsDialog(
                project: project,
                sshTargets: <SshTarget>[
                  _target('ssh-mac', 'Build Mac', runtimePlatform: 'macos'),
                  _target('ssh-win', 'Build PC', runtimePlatform: 'windows'),
                  _target(
                    'ssh-staging',
                    'Staging',
                    bootstrapStatus: SshBootstrapStatus.notInstalled,
                  ),
                ],
                loadHosts: runtime.list,
                addProjectToHost: runtime.add,
                removeFromHost: runtime.remove,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

SshTarget _target(
  String id,
  String alias, {
  String? runtimePlatform,
  SshBootstrapStatus bootstrapStatus = SshBootstrapStatus.installed,
}) {
  return SshTarget(
    id: id,
    alias: alias,
    host: '$id.example.test',
    port: 22,
    username: 'leynier',
    authKind: SshAuthKind.agent,
    createdAt: _now,
    updatedAt: _now,
    runtimePlatform: runtimePlatform,
    bootstrapStatus: bootstrapStatus,
  );
}
