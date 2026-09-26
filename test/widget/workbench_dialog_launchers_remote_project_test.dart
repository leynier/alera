import 'dart:async';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/infra/runtime_project_hosts_client.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workbench_dialog_launchers_test_support.dart';

final DateTime _now = DateTime.utc(2026, 9, 21);

void main() {
  Future<void> openAddProject(
    WidgetTester tester, {
    required bool projectHostsSupported,
    required List<SshTarget> sshTargets,
    DialogLaunchersTestController? controller,
    RuntimeProjectHostsClient? client,
  }) async {
    await pumpFlowHarness(
      tester,
      controller:
          controller ?? DialogLaunchersTestController(const WorkbenchState()),
      onPressed: (context, ref) => showAddProjectFlow(context, ref),
      projectHostsSupported: projectHostsSupported,
      sshTargets: sshTargets,
      projectHostsClient: client,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Add Remote Project is hidden without the runtime capability', (
    tester,
  ) async {
    await openAddProject(
      tester,
      projectHostsSupported: false,
      sshTargets: <SshTarget>[_target('ssh-mac', 'Build Mac')],
    );

    expect(find.text('Clone From URL'), findsOneWidget);
    expect(find.text('Add Remote Project'), findsNothing);
  });

  testWidgets('Add Remote Project is hidden without a bootstrapped host', (
    tester,
  ) async {
    await openAddProject(
      tester,
      projectHostsSupported: true,
      sshTargets: <SshTarget>[
        _target(
          'ssh-staging',
          'Staging',
          bootstrapStatus: SshBootstrapStatus.notInstalled,
        ),
      ],
    );

    expect(find.text('Clone From URL'), findsOneWidget);
    expect(find.text('Add Remote Project'), findsNothing);
  });

  testWidgets('registers the project on the host without navigating', (
    tester,
  ) async {
    final requests = <(String, Map<String, Object?>)>[];
    final controller = _RecordingController();
    await openAddProject(
      tester,
      projectHostsSupported: true,
      sshTargets: <SshTarget>[_target('ssh-mac', 'Build Mac')],
      controller: controller,
      client: RuntimeProjectHostsClient((type, payload, timeout) async {
        requests.add((type, payload));
        return _registered;
      }),
    );

    await tester.tap(find.text('Add Remote Project'));
    await tester.pumpAndSettle();
    expect(find.text('Clone From URL'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Folder on the Host'),
      '/srv/api',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Project'));
    await tester.pumpAndSettle();

    expect(requests.single.$1, 'project.registerRemote');
    expect(requests.single.$2, <String, Object?>{
      'hostId': 'ssh-mac',
      'path': '/srv/api',
      'kind': 'gitRepository',
    });
    expect(find.text('Api added'), findsOneWidget);
    expect(find.text('Folder on the Host'), findsNothing);
    // The project list follows `projectsChanged`; nothing is selected here.
    expect(controller.addedLocalPath, isNull);
    expect(controller.clonedProjectCall, isNull);
    expect(controller.createdWorkspaceCall, isNull);
    expect(controller.activatedProjects, isEmpty);
  });

  testWidgets('a clone that outlives the dialog reports its outcome', (
    tester,
  ) async {
    final answer = Completer<Object?>();
    await openAddProject(
      tester,
      projectHostsSupported: true,
      sshTargets: <SshTarget>[_target('ssh-mac', 'Build Mac')],
      client: RuntimeProjectHostsClient((type, payload, timeout) {
        return answer.future;
      }),
    );

    await tester.tap(find.text('Add Remote Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clone Repository'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Git URL'),
      'git@github.com:o/api.git',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Project'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Git URL'), findsNothing);

    answer.completeError(StateError('git clone failed: repository not found'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('git clone failed: repository not found'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });
}

class _RecordingController extends DialogLaunchersTestController {
  _RecordingController() : super(const WorkbenchState());

  final List<String> activatedProjects = <String>[];

  @override
  Future<void> activateAddedProject(Project project) async {
    activatedProjects.add(project.id);
  }
}

final Map<String, Object?> _registered = <String, Object?>{
  'project': <String, Object?>{
    'id': 'project-remote',
    'name': 'Api',
    'repoPath': '/srv/api',
    'createdAt': _now.toIso8601String(),
    'updatedAt': _now.toIso8601String(),
    'kind': 'gitRepository',
  },
  'checkout': <String, Object?>{'hostId': 'ssh-mac', 'path': '/srv/api'},
};

SshTarget _target(
  String id,
  String alias, {
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
    runtimePlatform: 'macos',
    bootstrapStatus: bootstrapStatus,
  );
}
