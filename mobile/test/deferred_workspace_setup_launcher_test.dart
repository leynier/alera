import 'dart:convert';

import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/deferred_workspace_setup_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  test('Starts deferred setup in a detached Setup terminal', () async {
    final client = FakeTerminalClient();
    addTearDown(client.dispose);
    final creation = WorkspaceCreationResult(
      workspace: const WorkspaceSummary(
        id: 'workspace-1',
        projectId: 'project-1',
        name: 'Feature',
        path: '/workspaces/feature',
      ),
      steps: const <WorkspaceSetupStep>[],
      deferredSetupCommand: '/bin/sh "/runtime/setup.sh"',
    );

    final result = await launchDeferredWorkspaceSetup(client, creation);

    expect(result.setupLaunchError, isNull);
    expect(client.calls, <String>[
      'create workspace-1 Setup',
      'write session-created-1 27 paste=false enter=true',
      'detach session-created-1',
    ]);
    expect(utf8.decode(client.writes.single), '/bin/sh "/runtime/setup.sh"');
  });

  test('Falls back to an inline carriage return for an older host', () async {
    final client = FakeTerminalClient()..supportsDeferredTerminalInput = false;
    addTearDown(client.dispose);
    final creation = WorkspaceCreationResult(
      workspace: const WorkspaceSummary(
        id: 'workspace-1',
        projectId: 'project-1',
        name: 'Feature',
        path: '/workspaces/feature',
      ),
      steps: const <WorkspaceSetupStep>[],
      deferredSetupCommand: 'cmd /d /c "C:\\runtime\\setup.cmd"',
    );

    await launchDeferredWorkspaceSetup(client, creation);

    expect(
      utf8.decode(client.writes.single),
      'cmd /d /c "C:\\runtime\\setup.cmd"\r',
    );
    expect(client.calls, contains('detach session-created-1'));
  });
}
