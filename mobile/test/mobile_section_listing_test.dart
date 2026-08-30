import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 30);
  final sections = [
    WorkspaceSectionSummary(
      id: 'a',
      name: 'Alpha',
      createdAt: now,
      updatedAt: now,
    ),
    WorkspaceSectionSummary(
      id: 'b',
      name: 'Beta',
      createdAt: now,
      updatedAt: now.add(const Duration(days: 1)),
    ),
  ];
  const workspaces = [
    WorkspaceSummary(
      id: 'parent',
      projectId: 'p',
      name: 'Parent',
      path: '/p',
      sectionId: 'a',
    ),
    WorkspaceSummary(
      id: 'child',
      projectId: 'q',
      name: 'Child',
      path: '/c',
      sectionId: 'b',
      parentWorkspaceId: 'parent',
    ),
    WorkspaceSummary(id: 'other', projectId: 'p', name: 'Other', path: '/o'),
  ];
  const prefs = MobileViewPrefs(groupBy: MobileWorkspaceGroupBy.section);
  test('activity sort ranks only section members with Others last', () {
    final rows = buildMobileWorkspaceRows(
      workspaces: workspaces,
      projects: [],
      sections: sections,
      prefs: prefs.copyWith(sectionSort: MobileWorkbenchSortBy.activity),
      terminalTabCountByWorkspaceId: {'parent': 1, 'child': 1},
      activity: {'parent': now, 'child': now.add(const Duration(minutes: 1))},
    );
    expect(
      rows.whereType<MobileCustomSectionHeaderRow>().map(
        (row) => row.section?.name ?? 'Others',
      ),
      ['Beta', 'Alpha', 'Others'],
    );
  });

  test('mixed projects and parents in different sections stay visible with Others last', () {
    final rows = buildMobileWorkspaceRows(
      workspaces: workspaces,
      projects: [],
      sections: sections,
      prefs: prefs,
    );
    expect(
      rows.whereType<MobileCustomSectionHeaderRow>().map(
        (row) => row.section?.name ?? 'Others',
      ),
      ['Alpha', 'Beta', 'Others'],
    );
    expect(
      rows.whereType<MobileWorkspaceEntryRow>().every(
        (row) => row.entry.depth == 0,
      ),
      isTrue,
    );
    final recent = buildMobileWorkspaceRows(
      workspaces: workspaces,
      projects: [],
      sections: sections,
      prefs: prefs.copyWith(sectionSort: MobileWorkbenchSortBy.recent),
    );
    expect(
      recent.whereType<MobileCustomSectionHeaderRow>().first.section!.name,
      'Beta',
    );
  });
  test('search by section, collapsed Others and preferences roundtrip', () {
    final rows = buildMobileWorkspaceRows(
      workspaces: workspaces,
      projects: [],
      sections: sections,
      prefs: prefs,
      searchQuery: 'Alpha',
    );
    expect(
      rows.whereType<MobileWorkspaceEntryRow>().single.entry.workspace.id,
      'parent',
    );
    final collapsed = prefs.copyWith(
      collapsedSectionIds: {'a'},
      othersSectionCollapsed: true,
    );
    final visible = buildMobileWorkspaceRows(
      workspaces: workspaces,
      projects: [],
      sections: sections,
      prefs: collapsed,
    );
    expect(
      visible.whereType<MobileWorkspaceEntryRow>().single.entry.workspace.id,
      'child',
    );
    final restored = MobileViewPrefs.fromJson(collapsed.toJson());
    expect(restored.groupBy, MobileWorkspaceGroupBy.section);
    expect(restored.collapsedSectionIds, {'a'});
    expect(restored.othersSectionCollapsed, isTrue);
    expect(
      MobileViewPrefs.fromJson({}).sectionSort,
      MobileWorkbenchSortBy.name,
    );
  });
}
