import 'package:alera_mobile/src/features/projects/domain/project_management_models.dart';
import 'package:alera_mobile/src/features/projects/presentation/project_removal_dialog.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_removal_dependency.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final confirm in [false, true]) {
    testWidgets('Project dependency dialog returns confirmation $confirm', (
      tester,
    ) async {
      bool? decision;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  decision = await showProjectRemovalDialog(
                    context,
                    projectName: 'Empty Project',
                    preview: const ProjectRemovalPreview(
                      workspaceCount: 0,
                      tabCount: 0,
                      activeSessionCount: 0,
                      hasConfigOverride: false,
                    ),
                    dependencies: const [
                      WorkspaceRemovalDependency(
                        id: 'automation',
                        name: 'Nightly Check',
                        activeRuns: 2,
                        requiresPause: true,
                      ),
                    ],
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
        find.textContaining('Nightly Check: 2 active runs'),
        findsOneWidget,
      );
      expect(find.textContaining('0 workspaces'), findsOneWidget);
      expect(decision, isNull);
      await tester.tap(find.text(confirm ? 'Pause And Remove' : 'Cancel'));
      await tester.pumpAndSettle();
      expect(decision, confirm);
    });
  }
}
