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
}
