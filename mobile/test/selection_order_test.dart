import 'package:alera_mobile/src/features/runtime/domain/project_selection_order.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/workbench/domain/workspace_parent_selection_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects sort alphabetically without mutating the source list', () {
    final projects = <ProjectSummary>[
      _project(id: 'zulu', name: 'zulu'),
      _project(id: 'alera-lower', name: 'alera'),
      _project(id: 'orca', name: 'Orca'),
      _project(id: 'alera-upper', name: 'Alera'),
    ];

    final sorted = sortProjectsForSelection(projects);

    expect(sorted.map((project) => project.id), <String>[
      'alera-upper',
      'alera-lower',
      'orca',
      'zulu',
    ]);
    expect(projects.map((project) => project.id), <String>[
      'zulu',
      'alera-lower',
      'orca',
      'alera-upper',
    ]);
  });

  test('parent choices prioritize the current project and its default', () {
    final choices =
        <WorkspaceParentSelectionKey>[
          _parent(
            projectId: 'project-alera',
            projectName: 'Alera',
            workspaceId: 'alera-feature',
            workspaceName: 'Feature',
          ),
          _parent(
            projectId: 'project-orca',
            projectName: 'Orca',
            workspaceId: 'orca-zulu',
            workspaceName: 'Zulu',
          ),
          _parent(
            projectId: 'project-alera',
            projectName: 'Alera',
            workspaceId: 'alera-main',
            workspaceName: 'Alera',
            isDefault: true,
          ),
          _parent(
            projectId: 'project-orca',
            projectName: 'Orca',
            workspaceId: 'orca-main',
            workspaceName: 'Orca',
            isDefault: true,
          ),
          _parent(
            projectId: 'project-orca',
            projectName: 'Orca',
            workspaceId: 'orca-alpha',
            workspaceName: 'Alpha',
          ),
        ]..sort(
          (left, right) => compareWorkspaceParentSelectionKeys(
            left,
            right,
            preferredProjectId: 'project-orca',
          ),
        );

    expect(choices.map((choice) => choice.workspaceId), <String>[
      'orca-main',
      'orca-alpha',
      'orca-zulu',
      'alera-main',
      'alera-feature',
    ]);
  });
}

ProjectSummary _project({required String id, required String name}) {
  return ProjectSummary(id: id, name: name, repoPath: '/repo/$id');
}

WorkspaceParentSelectionKey _parent({
  required String projectId,
  required String projectName,
  required String workspaceId,
  required String workspaceName,
  bool isDefault = false,
}) {
  return (
    isDefault: isDefault,
    projectId: projectId,
    projectName: projectName,
    workspaceId: workspaceId,
    workspaceName: workspaceName,
  );
}
