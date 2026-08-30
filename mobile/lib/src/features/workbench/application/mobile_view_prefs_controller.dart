import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_view_prefs_controller.g.dart';

@riverpod
class MobileViewPrefsController extends _$MobileViewPrefsController {
  @override
  Future<MobileViewPrefs> build(String hostId) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    if (!client.supportsWorkspaceSidebarParity) {
      throw UnsupportedError(
        'Update Alera on this host to use mobile workspaces.',
      );
    }
    final subscription = client.events.listen((event) {
      if (event.name == 'workbenchViewPrefsChanged') {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(subscription.cancel);
    return client.loadWorkbenchViewPrefs();
  }

  Future<void> setGroupBy(MobileWorkspaceGroupBy groupBy) {
    return _update((prefs) => prefs.copyWith(groupBy: groupBy));
  }

  Future<void> togglePinnedSection() {
    return _update(
      (prefs) =>
          prefs.copyWith(pinnedSectionCollapsed: !prefs.pinnedSectionCollapsed),
    );
  }

  Future<void> toggleAllSection() {
    return _update(
      (prefs) =>
          prefs.copyWith(allSectionCollapsed: !prefs.allSectionCollapsed),
    );
  }

  Future<void> setSectionSort(MobileWorkbenchSortBy value) =>
      _update((prefs) => prefs.copyWith(sectionSort: value));

  Future<void> toggleSectionCollapsed(String? id) => _update(
    (prefs) => id == null
        ? prefs.copyWith(othersSectionCollapsed: !prefs.othersSectionCollapsed)
        : prefs.copyWith(
            collapsedSectionIds: _toggled(prefs.collapsedSectionIds, id),
          ),
  );

  Future<void> setProjectSort(MobileWorkbenchSortBy value) {
    return _update((prefs) => prefs.copyWith(projectSort: value));
  }

  Future<void> setWorkspaceSort(MobileWorkbenchSortBy value) {
    return _update((prefs) => prefs.copyWith(workspaceSort: value));
  }

  Future<void> setKindFilter(MobileWorkspaceKindFilter value) {
    return _update((prefs) => prefs.copyWith(workspaceKindFilter: value));
  }

  Future<void> setShowActiveWorkspacesOnly(bool show) {
    return _update((prefs) => prefs.copyWith(showActiveWorkspacesOnly: show));
  }

  Future<void> setShowPinnedWorkspacesBelow(bool show) {
    return _update((prefs) => prefs.copyWith(showPinnedWorkspacesBelow: show));
  }

  Future<void> setProjectFilter(Set<String> ids) {
    return _update((prefs) => prefs.copyWith(selectedProjectIds: ids));
  }

  Future<void> setTagFilter(Set<String> ids) {
    return _update((prefs) => prefs.copyWith(selectedTagIds: ids));
  }

  Future<void> toggleProjectCollapsed(String projectId) {
    return _update(
      (prefs) => prefs.copyWith(
        collapsedProjectIds: _toggled(prefs.collapsedProjectIds, projectId),
      ),
    );
  }

  Future<void> toggleParentCollapsed(String workspaceId) {
    return _update(
      (prefs) => prefs.copyWith(
        collapsedParentWorkspaceIds: _toggled(
          prefs.collapsedParentWorkspaceIds,
          workspaceId,
        ),
      ),
    );
  }

  Future<void> _update(
    MobileViewPrefs Function(MobileViewPrefs) transform,
  ) async {
    final current = await future;
    final next = transform(current).copyWith(revision: current.revision);
    state = AsyncData(next);
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      state = AsyncData(await client.updateWorkbenchViewPrefs(next));
    } on Object {
      ref.invalidateSelf();
      rethrow;
    }
  }

  Set<String> _toggled(Set<String> ids, String id) {
    final next = <String>{...ids};
    if (!next.remove(id)) {
      next.add(id);
    }
    return next;
  }
}
