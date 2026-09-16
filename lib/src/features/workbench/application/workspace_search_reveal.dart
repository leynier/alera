import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_search_reveal.g.dart';

/// A keyboard request to bring the workspace search inputs into focus.
///
/// Showing the Search panel is not enough when it is already open: the query
/// field autofocuses only on mount, and the replace row is local panel state.
/// The panel consumes the request (see [WorkspaceSearchReveal.consume]) so a
/// panel mounted later does not replay a stale one.
class const WorkspaceSearchRevealRequest({
  required final int generation,
  required final bool replace,
});

@Riverpod(keepAlive: true)
class WorkspaceSearchReveal extends _$WorkspaceSearchReveal {
  @override
  WorkspaceSearchRevealRequest? build() => null;

  void request({required bool replace}) {
    state = WorkspaceSearchRevealRequest(
      generation: (state?.generation ?? 0) + 1,
      replace: replace,
    );
  }

  /// Clears [request] once the panel has acted on it. A newer request is left
  /// in place.
  void consume(WorkspaceSearchRevealRequest request) {
    if (state?.generation == request.generation) {
      state = null;
    }
  }
}
