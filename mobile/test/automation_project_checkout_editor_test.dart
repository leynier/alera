import 'package:alera_mobile/src/features/automations/domain/mobile_automation.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Project folder choices exclude duplicate host values from worktrees',
    () {
      final choices = mobileProjectFolderChoices([
        {'kind': 'project', 'hostId': 'local', 'path': '/repo'},
        {'kind': 'linked', 'hostId': 'local', 'path': '/worktrees/one'},
        {'kind': 'project', 'hostId': 'ssh-test', 'path': '/remote/repo'},
        {
          'kind': 'linked',
          'hostId': 'ssh-test',
          'path': '/remote/worktrees/two',
        },
      ]);
      expect(choices.map((choice) => choice.id), ['local', 'ssh-test']);
      expect(choices.map((choice) => choice.label), [
        'local: /repo',
        'ssh-test: /remote/repo',
      ]);
    },
  );
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
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  result = await showMobileAutomationEditor(
                    context,
                    initial: MobileAutomation.fromJson({
                      'id': 'automation',
                      'name': 'Nightly Check',
                      'slug': 'nightly',
                      'promptTemplate': 'Review the current files',
                      'target': {'projectCheckout': target},
                    }),
                    options: const MobileAutomationEditorOptions(
                      projects: [],
                      workspaces: [],
                      profiles: [],
                      tabs: [],
                    ),
                  );
                },
                child: const Text('Open'),
              );
            },
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
