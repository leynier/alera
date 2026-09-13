import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/presentation/automation_editor_dialog.dart';
import 'package:alera/src/features/automations/application/automation_project_checkouts.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Project folder choices exclude linked paths on the same host', () {
    final choices = projectFolderChoices([
      {'kind': 'project', 'hostId': 'local', 'path': '/repo'},
      {'kind': 'linked', 'hostId': 'local', 'path': '/worktrees/one'},
      {'kind': 'project', 'hostId': 'ssh-test', 'path': '/remote/repo'},
      {'kind': 'linked', 'hostId': 'ssh-test', 'path': '/remote/worktrees/two'},
    ]);
    expect(choices, [
      (hostId: 'local', path: '/repo'),
      (hostId: 'ssh-test', path: '/remote/repo'),
    ]);
  });
  for (final host in ['local', 'ssh-test']) {
    testWidgets('Project folder target preserves $host without a workspace', (
      tester,
    ) async {
      final target = <String, Object?>{
        'projectId': 'empty-project',
        'hostId': host,
        'nameTemplate': '{{automation.name}} {{run.number}}',
        'agentProfileId': 'profile',
      };
      Map<String, Object?>? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectListProvider.overrideWith((ref) => Stream.value([])),
            agentProfilesProvider.overrideWith(_Profiles.new),
            workbenchControllerProvider.overrideWith(_Workbench.new),
            automationProjectCheckoutsProvider('empty-project')
                .overrideWith((ref) async => [(hostId: host, path: '/repo')]),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    result = await showAutomationEditorDialog(
                      context,
                      initial: AutomationRecord.fromJson({
                        'id': 'automation',
                        'name': 'Nightly Check',
                        'slug': 'nightly',
                        'promptTemplate': 'Review the current files',
                        'target': {'projectCheckout': target},
                      }),
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Workspace'),
        findsNothing,
      );
      expect(find.widgetWithText(TextField, 'Source Branch'), findsNothing);
      await tester.ensureVisible(find.text('Save Automation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Automation'));
      await tester.pumpAndSettle();
      expect(result?['target'], {'projectCheckout': target});
      expect(result?['projectId'], 'empty-project');
      expect(result?['cleanupPolicy'], 'preserve');
    });
  }
}

class _Profiles extends AgentProfiles {
  @override
  Future<List<AgentProfile>> build() async => const [];
}

class _Workbench extends WorkbenchController {
  @override
  WorkbenchState build() => const WorkbenchState();
}
