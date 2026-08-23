import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_workspace_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  test(
    'Creates a workspace identity and launches the selected profile',
    () async {
      final client = FakeTerminalClient()
        ..projectBranches = const <String>['develop', 'main'];
      final container = ProviderContainer(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.dispose);
      final subscription = container.listen(
        promptWorkspaceControllerProvider('host-1'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final controller = container.read(
        promptWorkspaceControllerProvider('host-1').notifier,
      );

      await controller.selectProject('project-1');
      var state = container.read(promptWorkspaceControllerProvider('host-1'));
      expect(state.sourceBranch, 'main');
      expect(state.profileId, 'profile-1');

      await controller.create(
        prompt: 'Add offline support',
        workspaceBranches: const <String>{},
      );
      state = container.read(promptWorkspaceControllerProvider('host-1'));

      expect(state.creation?.workspace.id, 'created');
      expect(state.agentTabId, 'agent-tab');
      expect(
        client.calls,
        containsAll(<String>[
          'generateWorkspaceIdentity project-1',
          'createWorkspace project-1 feat/generated-workspace',
          'launchAgentProfile created profile-1 Add offline support',
        ]),
      );
    },
  );

  test(
    'Uses the configured profile, links the parent, and starts Setup after Agent',
    () async {
      final client = FakeTerminalClient()
        ..projectBranches = const <String>['main']
        ..agentProfiles = const <AgentProfileSummary>[
          AgentProfileSummary(
            id: 'profile-1',
            name: 'Codex',
            agentType: 'codex',
          ),
          AgentProfileSummary(
            id: 'profile-2',
            name: 'Claude Code',
            agentType: 'claude',
          ),
        ]
        ..deferredSetupCommand = '/bin/sh "/runtime/setup.sh"'
        ..linkError = StateError('Parent link rejected');
      final container = ProviderContainer(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
          terminalClientProvider('host-1').overrideWith((ref) async => client),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.dispose);
      final subscription = container.listen(
        promptWorkspaceControllerProvider('host-1'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final controller = container.read(
        promptWorkspaceControllerProvider('host-1').notifier,
      );

      await controller.selectProject(
        'project-1',
        defaultAgentProfileId: 'profile-2',
      );
      expect(
        container.read(promptWorkspaceControllerProvider('host-1')).profileId,
        'profile-2',
      );

      await controller.create(
        prompt: 'Add offline support',
        workspaceBranches: const <String>{},
        parentWorkspaceId: 'parent-1',
      );
      final state = container.read(promptWorkspaceControllerProvider('host-1'));

      expect(state.creation?.parentLinkError, contains('Parent link rejected'));
      final agentIndex = client.calls.indexOf(
        'launchAgentProfile created profile-2 Add offline support',
      );
      final setupIndex = client.calls.indexOf('create created Setup');
      expect(agentIndex, greaterThanOrEqualTo(0));
      expect(setupIndex, greaterThan(agentIndex));
      expect(client.calls, contains('link parent-1 created'));
    },
  );

  test('Retries agent launch with the original mutation id', () async {
    final client = FakeTerminalClient()
      ..projectBranches = const <String>['main']
      ..launchFailuresRemaining = 1;
    final container = ProviderContainer(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.dispose);
    final subscription = container.listen(
      promptWorkspaceControllerProvider('host-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final controller = container.read(
      promptWorkspaceControllerProvider('host-1').notifier,
    );

    await controller.selectProject('project-1');
    await controller.create(
      prompt: 'Add offline support',
      workspaceBranches: const <String>{},
    );
    expect(
      container.read(promptWorkspaceControllerProvider('host-1')).error,
      contains('launch response was lost'),
    );

    await controller.retryAgent('Add offline support');

    expect(
      container.read(promptWorkspaceControllerProvider('host-1')).agentTabId,
      'agent-tab',
    );
    expect(client.agentLaunchMutationIds, hasLength(2));
    expect(client.agentLaunchMutationIds[1], client.agentLaunchMutationIds[0]);
  });

  test(
    'Refuses a retry after a new host is replaced by an older host',
    () async {
      final client = FakeTerminalClient()
        ..projectBranches = const <String>['main']
        ..launchFailuresRemaining = 1;
      final container = ProviderContainer(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.dispose);
      final subscription = container.listen(
        promptWorkspaceControllerProvider('host-1'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final controller = container.read(
        promptWorkspaceControllerProvider('host-1').notifier,
      );

      await controller.selectProject('project-1');
      await controller.create(
        prompt: 'Add offline support',
        workspaceBranches: const <String>{},
      );
      client.supportsIdempotentAgentProfileLaunch = false;
      await controller.retryAgent('Add offline support');

      final state = container.read(promptWorkspaceControllerProvider('host-1'));
      expect(state.error, contains('before retrying agent launch safely'));
      expect(client.agentLaunchMutationIds, hasLength(1));
    },
  );

  test('Refuses a retry when the original host lacked idempotency', () async {
    final client = FakeTerminalClient()
      ..projectBranches = const <String>['main']
      ..launchFailuresRemaining = 1
      ..supportsIdempotentAgentProfileLaunch = false;
    final container = ProviderContainer(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.dispose);
    final subscription = container.listen(
      promptWorkspaceControllerProvider('host-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final controller = container.read(
      promptWorkspaceControllerProvider('host-1').notifier,
    );

    await controller.selectProject('project-1');
    await controller.create(
      prompt: 'Add offline support',
      workspaceBranches: const <String>{},
    );
    client.supportsIdempotentAgentProfileLaunch = true;
    await controller.retryAgent('Add offline support');

    final state = container.read(promptWorkspaceControllerProvider('host-1'));
    expect(state.error, contains('before retrying agent launch safely'));
    expect(client.agentLaunchMutationIds, hasLength(1));
  });
}
