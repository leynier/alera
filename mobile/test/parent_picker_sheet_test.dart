import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/presentation/parent_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows the current project first with its default workspace first',
    (tester) async {
      final child = _workspace(
        id: 'orca-child',
        projectId: 'project-orca',
        name: 'Current',
      );
      String? selectedId;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  selectedId = await showParentPickerSheet(
                    context,
                    child: child,
                    projects: const <ProjectSummary>[
                      ProjectSummary(
                        id: 'project-orca',
                        name: 'Orca',
                        repoPath: '/repo/orca',
                      ),
                      ProjectSummary(
                        id: 'project-alera',
                        name: 'Alera',
                        repoPath: '/repo/alera',
                      ),
                    ],
                    workspaces: <WorkspaceSummary>[
                      _workspace(
                        id: 'alera-feature',
                        projectId: 'project-alera',
                        name: 'Alera Feature',
                      ),
                      _workspace(
                        id: 'orca-zulu',
                        projectId: 'project-orca',
                        name: 'Zulu',
                      ),
                      _workspace(
                        id: 'alera-main',
                        projectId: 'project-alera',
                        name: 'Alera Default',
                        isDefault: true,
                      ),
                      child,
                      _workspace(
                        id: 'orca-main',
                        projectId: 'project-orca',
                        name: 'Orca Default',
                        isDefault: true,
                      ),
                      _workspace(
                        id: 'orca-alpha',
                        projectId: 'project-orca',
                        name: 'Alpha',
                      ),
                    ],
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

      final titles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title! as Text).data)
          .toList();
      expect(titles, <String?>[
        'Orca Default',
        'Alpha',
        'Zulu',
        'Alera Default',
      ]);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(selectedId, 'orca-alpha');
    },
  );
}

WorkspaceSummary _workspace({
  required String id,
  required String projectId,
  required String name,
  bool isDefault = false,
}) {
  return WorkspaceSummary(
    id: id,
    projectId: projectId,
    name: name,
    path: '/repo/$projectId/$id',
    kind: isDefault ? 'main' : 'linked',
  );
}
