import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_actions_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_commit_draft.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'commit_message_generation_controller.g.dart';

/// Generates a commit message on the runtime for one workspace. The state is
/// the operation id of the run in flight, which is also what cancels it.
@riverpod
class CommitMessageGenerationController
    extends _$CommitMessageGenerationController {
  MobileWorkspacePanelsClient? _client;
  String? _running;

  /// The run the user stopped. Its result is dropped when it returns, while
  /// `state` keeps the button in its Stop shape until then.
  String? _cancelled;

  @override
  String? build(String hostId, String workspaceId) {
    ref.onDispose(() {
      // Leaving the panel mid-run would otherwise keep an agent working for
      // an answer nobody will see. Ref is unusable here, hence the fields.
      if ((_client, _running) case (final client?, final operationId?)) {
        unawaited(_cancelQuietly(client, operationId));
      }
    });
    return null;
  }

  /// Resolves with a message to show when generation failed, or null. The
  /// result only replaces the draft when the user has not edited it since.
  Future<String?> generate() async {
    if (state != null) {
      return null;
    }
    final operationId =
        'mobile-commit-${DateTime.now().microsecondsSinceEpoch}';
    state = operationId;
    _running = operationId;
    final draftProvider = sourceControlCommitDraftProvider(hostId, workspaceId);
    final draftAtStart = ref.read(draftProvider);
    try {
      final client = await ref.read(workspaceClientProvider(hostId).future);
      if (client case final MobileWorkspacePanelsClient panels
          when panels.supportsCommitMessageGeneration) {
        _client = panels;
        if (_cancelled == operationId) {
          return null;
        }
        final generated = await panels.generateCommitMessage(
          operationId: operationId,
          workspaceId: workspaceId,
        );
        if (!ref.mounted || _cancelled == operationId) {
          return null;
        }
        if (ref.read(draftProvider) == draftAtStart) {
          ref.read(draftProvider.notifier).update(generated.message);
        }
        return null;
      }
      return 'Update the paired Alera runtime to generate commit messages.';
    } on Object catch (error) {
      if (!ref.mounted || _cancelled == operationId) {
        return null;
      }
      return sourceControlErrorMessage(error);
    } finally {
      if (_running == operationId) {
        _running = null;
      }
      if (ref.mounted && state == operationId) {
        state = null;
      }
    }
  }

  /// Asks the runtime to drop the run, but keeps the generating state until
  /// the in-flight request returns. Clearing it here would let Generate start
  /// a second agent while the first is still running, because the host keys
  /// active runs by `operationId` and would happily run both.
  Future<void> cancel() async {
    final operationId = state;
    final client = _client;
    if (operationId == null) {
      return;
    }
    _cancelled = operationId;
    if (client == null) {
      // The client never resolved, so nothing reached the runtime to cancel.
      _running = null;
      state = null;
      return;
    }
    await _cancelQuietly(client, operationId);
  }
}

/// Cancelling is best effort: the runtime also drops the run when it ends.
Future<void> _cancelQuietly(
  MobileWorkspacePanelsClient client,
  String operationId,
) async {
  try {
    await client.cancelCommitMessage(operationId);
  } on Object {
    return;
  }
}
