import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 8, 21);

void main() {
  group('active workspace filter', () {
    test('shows terminal and Codex workspaces and hides empty projects', () {
      final alera = _project('p-alera');
      final orca = _project('p-orca');
      final terminal = _workspace('w-terminal', alera.id);
      final codex = _workspace('w-codex', alera.id);
      final editor = _workspace('w-editor', alera.id);
      final inactive = _workspace('w-inactive', orca.id);
      final state = WorkbenchState(
        projects: <Project>[alera, orca],
        workspacesByProject: <String, List<Workspace>>{
          alera.id: <Workspace>[terminal, codex, editor],
          orca.id: <Workspace>[inactive],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          terminal.id: <WorkspaceTabRecord>[
            _tab('t-terminal', terminal.id, WorkspaceTabKind.terminal),
          ],
          codex.id: <WorkspaceTabRecord>[
            _tab('t-codex', codex.id, WorkspaceTabKind.codex),
          ],
          editor.id: <WorkspaceTabRecord>[
            _tab('t-editor', editor.id, WorkspaceTabKind.editor),
          ],
        },
        viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
          showActiveWorkspacesOnly: true,
        ),
        bootstrapped: true,
      );

      final rows = buildSidebarRows(state);

      expect(workspaceOrderOfRows(rows), <String>['w-codex', 'w-terminal']);
      expect(
        rows.whereType<WorkbenchProjectHeaderRow>().map(
          (row) => row.project.id,
        ),
        <String>['p-alera'],
      );
      expect(countVisibleWorkspaces(state), 2);
      final targets = visibleSidebarCollapseTargets(state);
      expect(targets.projectIds, <String>{'p-alera'});
      expect(targets.workspaceIds, <String>{'w-terminal', 'w-codex'});
    });

    test('combines with kind, tag, and search filters', () {
      final project = _project('p-alera');
      final main = _workspace(
        'w-main',
        project.id,
        kind: WorkspaceKind.main,
        tagIds: <String>['review'],
      );
      final linked = _workspace(
        'w-feature',
        project.id,
        tagIds: <String>['review'],
      );
      final state = WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[main, linked],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          main.id: <WorkspaceTabRecord>[
            _tab('t-main', main.id, WorkspaceTabKind.terminal),
          ],
          linked.id: <WorkspaceTabRecord>[
            _tab('t-feature', linked.id, WorkspaceTabKind.terminal),
          ],
        },
        viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
          showActiveWorkspacesOnly: true,
          workspaceKindFilter: WorkspaceKindFilter.nonDefaultOnly,
          selectedTagIds: <String>{'review'},
        ),
        searchQuery: 'feature',
        bootstrapped: true,
      );

      expect(workspaceOrderOfRows(buildSidebarRows(state)), <String>[
        'w-feature',
      ]);
      expect(countVisibleWorkspaces(state), 1);
    });

    test('filters pinned copies and promotes active children', () {
      final project = _project('p-alera');
      final inactivePinned = _workspace('w-pinned', project.id, isPinned: true);
      final inactiveParent = _workspace('w-parent', project.id);
      final activeChild = _workspace(
        'w-child',
        project.id,
        parentWorkspaceId: inactiveParent.id,
      );
      final state = WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[inactivePinned, inactiveParent, activeChild],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          activeChild.id: <WorkspaceTabRecord>[
            _tab('t-child', activeChild.id, WorkspaceTabKind.codex),
          ],
        },
        viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
          showActiveWorkspacesOnly: true,
        ),
        bootstrapped: true,
      );

      final rows = buildSidebarRows(state);
      expect(
        rows.whereType<WorkbenchWorkspaceRow>().where(
          (row) => row.isPinnedCopy,
        ),
        isEmpty,
      );
      final child = rows.whereType<WorkbenchWorkspaceRow>().single;
      expect(child.workspace.id, activeChild.id);
      expect(child.indent, 1);
    });
  });
}

Project _project(String id) {
  return Project(
    id: id,
    name: id,
    repoPath: '/repo/$id',
    createdAt: _now,
    updatedAt: _now,
  );
}

Workspace _workspace(
  String id,
  String projectId, {
  WorkspaceKind kind = WorkspaceKind.linked,
  List<String> tagIds = const <String>[],
  String? parentWorkspaceId,
  bool isPinned = false,
}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: id,
    branch: id,
    path: '/repo/$projectId/$id',
    createdAt: _now,
    updatedAt: _now,
    kind: kind,
    status: WorkspaceStatus.active,
    tagIds: tagIds,
    parentWorkspaceId: parentWorkspaceId,
    isPinned: isPinned,
  );
}

WorkspaceTabRecord _tab(String id, String workspaceId, WorkspaceTabKind kind) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    kind: kind,
    title: id,
    createdAt: _now,
    updatedAt: _now,
  );
}
