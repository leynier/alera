part of 'workbench_controller.dart';

mixin _WorkbenchControllerSections
    on _$WorkbenchController, _WorkbenchControllerInternals {
  WorkspaceSectionRepository get _sectionRepository =>
      _repository as WorkspaceSectionRepository;

  void _startSections() {
    final repository = _repository;
    if (repository is! WorkspaceSectionRepository) return;
    // Keep watching unsupported hosts: an in-app update can add this capability.
    _sectionsSub = (repository as WorkspaceSectionRepository)
        .watchSections()
        .listen(
          (snapshot) {
            if (_disposed) return;
            final sections = snapshot.sections;
            final ids = sections.map((section) => section.id).toSet();
            state = state.copyWith(
              supportsSections: snapshot.supported,
              sections: sections,
              viewPrefs: state.viewPrefs.copyWith(
                groupBy:
                    !snapshot.supported &&
                        state.viewPrefs.groupBy == WorkbenchGroupBy.section
                    ? WorkbenchGroupBy.project
                    : state.viewPrefs.groupBy,
                collapsedSectionIds: snapshot.supported
                    ? state.viewPrefs.collapsedSectionIds.intersection(ids)
                    : state.viewPrefs.collapsedSectionIds,
                selectedSectionIds: snapshot.supported
                    ? state.viewPrefs.selectedSectionIds.intersection(ids)
                    : state.viewPrefs.selectedSectionIds,
              ),
            );
          },
          onError: (Object error) {
            if (!_disposed) {
              state = state.copyWith(error: 'Could not load sections: $error');
            }
          },
        );
  }

  Future<List<WorkspaceSection>> listWorkspaceSections() =>
      _sectionRepository.listSections();

  Future<void> saveWorkspaceSection(
    String workspaceId, {
    String? sectionId,
    String? newName,
  }) async {
    if (newName != null) {
      await _sectionRepository.createSection(newName, workspaceId);
    } else {
      await _sectionRepository.setSection(workspaceId, sectionId);
    }
  }

  /// Assigns or clears a section on [workspaceId] and every descendant.
  /// Creating a section still assigns the root atomically, then the rest.
  Future<void> saveWorkspaceSectionTree(
    String workspaceId, {
    String? sectionId,
    String? newName,
  }) async {
    final workspaces = <Workspace>[
      for (final group in state.workspacesByProject.values) ...group,
    ];
    final ids = <String>[
      workspaceId,
      ...workspaceIdsDescendedFrom(workspaces, workspaceId),
    ];
    var assignedId = sectionId;
    if (newName != null) {
      assignedId = (await _sectionRepository.createSection(
        newName,
        workspaceId,
      )).id;
    }
    for (final id in ids) {
      if (newName != null && id == workspaceId) {
        continue;
      }
      Workspace? current;
      for (final workspace in workspaces) {
        if (workspace.id == id) {
          current = workspace;
          break;
        }
      }
      if (current == null || current.sectionId == assignedId) {
        continue;
      }
      await _sectionRepository.setSection(id, assignedId);
    }
  }

  Future<void> deleteWorkspaceSection(String sectionId) =>
      _sectionRepository.removeSection(sectionId);

  void setSectionSort(WorkbenchSortBy sort) {
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(sectionSort: sort),
    );
    unawaited(_persistViewPrefs());
  }

  void toggleSectionCollapsed(String? sectionId) {
    final prefs = state.viewPrefs;
    if (sectionId == null) {
      state = state.copyWith(
        viewPrefs: prefs.copyWith(
          othersSectionCollapsed: !prefs.othersSectionCollapsed,
        ),
      );
    } else {
      final ids = {...prefs.collapsedSectionIds};
      if (!ids.add(sectionId)) ids.remove(sectionId);
      state = state.copyWith(
        viewPrefs: prefs.copyWith(collapsedSectionIds: ids),
      );
    }
    unawaited(_persistViewPrefs());
  }
}
