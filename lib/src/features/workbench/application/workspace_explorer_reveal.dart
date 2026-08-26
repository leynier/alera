import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_explorer_reveal.g.dart';

/// One-shot request to reveal a workspace-relative path in Explorer.
///
/// Source Control queues this, switches to the Explorer tab, and Explorer
/// consumes it after the tree is ready. The request is not persisted.
class WorkspaceExplorerRevealRequest {
  const WorkspaceExplorerRevealRequest({
    required this.workspaceId,
    required this.relativePath,
    required this.generation,
  });

  final String workspaceId;
  final String relativePath;
  final int generation;
}

@Riverpod(keepAlive: true)
class WorkspaceExplorerRevealController
    extends _$WorkspaceExplorerRevealController {
  int _generation = 0;

  @override
  WorkspaceExplorerRevealRequest? build() => null;

  void reveal({required String workspaceId, required String relativePath}) {
    _generation += 1;
    state = WorkspaceExplorerRevealRequest(
      workspaceId: workspaceId,
      relativePath: relativePath,
      generation: _generation,
    );
  }

  void consume(WorkspaceExplorerRevealRequest request) {
    if (state?.generation == request.generation) {
      state = null;
    }
  }
}
