import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_view_prefs_controller.g.dart';

@riverpod
class MobileViewPrefsController extends _$MobileViewPrefsController {
  @override
  Future<MobileViewPrefs> build(String hostId) {
    return ref.watch(viewPrefsRepositoryProvider).load(hostId);
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
    final next = transform(current);
    state = AsyncData(next);
    await ref.read(viewPrefsRepositoryProvider).save(hostId, next);
  }

  Set<String> _toggled(Set<String> ids, String id) {
    final next = <String>{...ids};
    if (!next.remove(id)) {
      next.add(id);
    }
    return next;
  }
}
