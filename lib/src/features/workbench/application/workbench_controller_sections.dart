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
