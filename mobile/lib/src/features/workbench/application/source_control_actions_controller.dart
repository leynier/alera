import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_commit_draft.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'source_control_actions_controller.g.dart';

/// Runs source control writes for one workspace and holds the one in flight,
/// so every control can disable itself while the runtime works.
///
/// Kept alive because a fetch or a push runs for minutes: the Source Control
/// panel is the only watcher, so an autoDispose family would drop the write
/// the moment the user switches to Explorer, re-enabling every control and
/// throwing away the snapshot the runtime is about to answer with.
@Riverpod(keepAlive: true)
class SourceControlActionsController extends _$SourceControlActionsController {
  @override
  MobileGitWriteAction? build(String hostId, String workspaceId) => null;

  /// Runs [write] and resolves with a message to show when it failed, or null
  /// when it succeeded. The snapshot the runtime answers with replaces the
  /// panel's; after a failure the panel reloads, because a composite write
  /// (commit then push) may have changed the tree before it failed.
  Future<String?> run(MobileGitWrite write) async {
    if (state != null) {
      return 'Another source control action is still running.';
    }
    state = write.action;
    SourceControlController status() =>
        ref.read(sourceControlControllerProvider(hostId, workspaceId).notifier);
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      if (client case final MobileWorkspacePanelsClient panels
          when panels.supportsSourceControlWrites) {
        final snapshot = await panels.gitWrite(workspaceId, write);
        if (ref.mounted) {
          status().apply(snapshot);
          _clearDraftAfterCommit(write);
        }
        return null;
      }
      return 'Update the paired Alera runtime to change source control from mobile.';
    } on Object catch (error) {
      if (ref.mounted) {
        unawaited(status().reload());
      }
      return sourceControlErrorMessage(error);
    } finally {
      if (ref.mounted) {
        state = null;
      }
    }
  }

  /// The composer may already be unmounted when the commit lands, so the draft
  /// is cleared here rather than from the widget. An amend edits its own
  /// message in a dialog and leaves the composer's draft alone.
  void _clearDraftAfterCommit(MobileGitWrite write) {
    if (write.action != MobileGitWriteAction.commit ||
        write.arguments['amend'] == true) {
      return;
    }
    ref
        .read(sourceControlCommitDraftProvider(hostId, workspaceId).notifier)
        .clear();
  }
}

/// Git failures already arrive worded the way desktop words them, so their
/// message is shown as-is. Everything else keeps its own text: a dropped
/// socket reads as "Could not reach the host", not as a git failure.
String sourceControlErrorMessage(Object error) => switch (error) {
  StateError(:final message) => message,
  UnsupportedError(:final message?) => message,
  TimeoutException() => 'The runtime did not answer in time.',
  _ => switch ('$error'.trim()) {
    '' => 'Git operation failed.',
    final message => message,
  },
};
