import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pull_request_controller.g.dart';

final Logger _logger = Logger('PullRequestController');

@riverpod
class PullRequestController extends _$PullRequestController {
  /// Bumped by every snapshot a write brings back and by every refresh, so a
  /// refresh that started before the write cannot roll the panel back to the
  /// state GitHub had then.
  int _generation = 0;

  @override
  Future<MobilePullRequestSnapshot> build(
    String hostId,
    String workspaceId,
  ) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    if (client case final MobileWorkspacePanelsClient panels
        when panels.supportsPullRequests) {
      return panels.pullRequestSnapshot(workspaceId);
    }
    throw UnsupportedError(
      'Update the paired Alera runtime to review pull requests.',
    );
  }

  /// Rebuilds in place: Riverpod carries the last snapshot through the
  /// loading and error states, so the panel keeps its content on screen.
  Future<void> reload() async {
    ref.invalidateSelf();
    try {
      await future;
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'could not refresh the pull request for $workspaceId',
        error,
        stackTrace,
      );
    }
  }

  /// Refresh, keeping what is on screen: a failure answers with the message to
  /// report instead of replacing a loaded snapshot with an error, and a result
  /// that a write overtook is dropped.
  Future<String?> refresh() async {
    final generation = ++_generation;
    final result = await AsyncValue.guard(() => build(hostId, workspaceId));
    if (generation != _generation) {
      return null;
    }
    if (result case AsyncError(:final error) when state.hasValue) {
      return pullRequestActionErrorMessage(error);
    }
    state = result;
    return switch (result) {
      AsyncError(:final error) => pullRequestActionErrorMessage(error),
      _ => null,
    };
  }

  /// A write already answered with the fresh snapshot.
  void applySnapshot(MobilePullRequestSnapshot snapshot) {
    _generation += 1;
    state = AsyncData(snapshot);
  }
}
