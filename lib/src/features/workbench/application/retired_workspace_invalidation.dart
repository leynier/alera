import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Invalidates the calling provider once [workspaceId] leaves workbench state.
///
/// A keepAlive family keyed by a workspace id outlives the workspace itself:
/// nothing disposes the instance when the workspace is deleted, so its state
/// (canvas catalogs, search results, review snapshots) stays in memory for the
/// rest of the session. Calling this from `build` retires the instance when
/// the workspace disappears; with no listeners left, invalidation disposes the
/// state instead of rebuilding it.
///
/// Edge-triggered on purpose: the workspace set is empty before the workbench
/// bootstraps, and a provider created in a harness without workbench state
/// must not invalidate itself in a loop.
void invalidateWhenWorkspaceRetired(Ref ref, String workspaceId) {
  ref.listen<bool>(
    workbenchControllerProvider.select(
      (state) => findWorkspaceById(state, workspaceId) != null,
    ),
    (previous, next) {
      if (previous == true && !next) {
        ref.invalidateSelf();
      }
    },
  );
}
