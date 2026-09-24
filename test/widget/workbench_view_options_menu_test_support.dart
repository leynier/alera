part of 'workbench_view_options_menu_test.dart';

Future<void> _pumpButton(
  WidgetTester tester,
  _ViewOptionsTestController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [workbenchControllerProvider.overrideWith(() => controller)],
      child: const MaterialApp(
        home: Scaffold(body: Center(child: WorkbenchViewOptionsButton())),
      ),
    ),
  );
  await tester.pump();
}

Finder _projectSearchField() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Add project\u2026',
  );
}

Finder _sectionSearchField() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Add section\u2026',
  );
}

Finder _optionSwitch(String title) {
  return find.descendant(
    of: find.ancestor(
      of: find.text(title),
      matching: find.byType(AleraSettingRow),
    ),
    matching: find.byType(Switch),
  );
}

Finder _viewOptionsButton() {
  return find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == 'View options',
  );
}

Finder _activeDot() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).shape == BoxShape.circle &&
        (widget.decoration! as BoxDecoration).color == AleraTokens.accent,
  );
}

Project _project(String id, String name) {
  final now = DateTime.utc(2026, 5, 25, 12);
  return Project(
    id: id,
    name: name,
    repoPath: '/repo/$id',
    createdAt: now,
    updatedAt: now,
  );
}

class _ViewOptionsTestController(final WorkbenchState _seed)
    extends WorkbenchController {
  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<List<WorkspaceTag>> listWorkspaceTags() async =>
      const <WorkspaceTag>[];

  @override
  void setGroupBy(WorkbenchGroupBy groupBy) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(groupBy: groupBy),
    );
  }

  @override
  void setProjectSort(WorkbenchSortBy sort) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(projectSort: sort),
    );
  }

  @override
  void setWorkspaceSort(WorkbenchSortBy sort) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(workspaceSort: sort),
    );
  }

  @override
  void addProjectFilter(String projectId) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        selectedProjectIds: <String>{
          ...state.viewPrefs.selectedProjectIds,
          projectId,
        },
      ),
    );
  }

  @override
  void removeProjectFilter(String projectId) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        selectedProjectIds: state.viewPrefs.selectedProjectIds
            .where((id) => id != projectId)
            .toSet(),
      ),
    );
  }

  @override
  void clearProjectFilters() {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(selectedProjectIds: <String>{}),
    );
  }

  @override
  void addSectionFilter(String sectionId) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        selectedSectionIds: <String>{
          ...state.viewPrefs.selectedSectionIds,
          sectionId,
        },
      ),
    );
  }

  @override
  void removeSectionFilter(String sectionId) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        selectedSectionIds: state.viewPrefs.selectedSectionIds
            .where((id) => id != sectionId)
            .toSet(),
      ),
    );
  }

  @override
  void clearSectionFilters() {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(selectedSectionIds: <String>{}),
    );
  }

  @override
  void setWorkspaceKindFilter(WorkspaceKindFilter filter) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(workspaceKindFilter: filter),
    );
  }

  @override
  void setShowActiveWorkspacesOnly(bool show) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(showActiveWorkspacesOnly: show),
    );
  }

  @override
  void setShowPinnedWorkspacesBelow(bool show) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(showPinnedWorkspacesBelow: show),
    );
  }

  @override
  void setShowArchivedWorkspaces(bool show) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(showArchivedWorkspaces: show),
    );
  }
}
