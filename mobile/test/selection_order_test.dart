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
      _project(id: 'alera-first', name: 'Alera'),
    ];

    final sorted = sortProjectsForSelection(projects);

    expect(sorted.map((project) => project.id), <String>[
      'alera-first',
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
      'alera-first',
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

  test(
    'parent choices use deterministic project and workspace tie-breakers',
    () {
      expect(
        compareWorkspaceParentSelectionKeys(
          _parent(
            projectId: 'project-alera',
            projectName: 'Alera',
            workspaceId: 'workspace-a',
            workspaceName: 'Workspace',
          ),
          _parent(
            projectId: 'project-beta',
            projectName: 'Beta',
            workspaceId: 'workspace-b',
            workspaceName: 'Workspace',
          ),
        ),
        isNegative,
      );
      expect(
        compareWorkspaceParentSelectionKeys(
          _parent(
            projectId: 'project-upper',
            projectName: 'Alera',
            workspaceId: 'workspace-a',
            workspaceName: 'Workspace',
          ),
          _parent(
            projectId: 'project-lower',
            projectName: 'alera',
            workspaceId: 'workspace-b',
            workspaceName: 'Workspace',
          ),
        ),
        isNegative,
      );
      expect(
        compareWorkspaceParentSelectionKeys(
          _parent(
            projectId: 'project-a',
            projectName: 'Alera',
            workspaceId: 'workspace-a',
            workspaceName: 'Workspace',
          ),
          _parent(
            projectId: 'project-b',
            projectName: 'Alera',
            workspaceId: 'workspace-b',
            workspaceName: 'Workspace',
          ),
        ),
        isNegative,
      );
      expect(
        compareWorkspaceParentSelectionKeys(
          _parent(
            projectId: 'project-a',
            projectName: 'Alera',
            workspaceId: 'workspace-upper',
            workspaceName: 'Feature',
          ),
          _parent(
            projectId: 'project-a',
            projectName: 'Alera',
            workspaceId: 'workspace-lower',
            workspaceName: 'feature',
          ),
        ),
        isNegative,
      );
      expect(
        compareWorkspaceParentSelectionKeys(
          _parent(
            projectId: 'project-a',
            projectName: 'Alera',
            workspaceId: 'workspace-a',
            workspaceName: 'Feature',
          ),
          _parent(
            projectId: 'project-a',
            projectName: 'Alera',
            workspaceId: 'workspace-b',
            workspaceName: 'Feature',
          ),
        ),
        isNegative,
      );
    },
  );
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
