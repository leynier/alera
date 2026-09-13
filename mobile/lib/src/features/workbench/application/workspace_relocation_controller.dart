import 'package:alera_mobile/src/features/runtime/domain/workspace_relocation_client.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/deferred_workspace_setup_launcher.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'workspace_relocation_controller.g.dart';

class const WorkspaceRelocationForm({
  required final String relocationId,
  final String branch = '',
  final String replacementBranch = '',
  final bool useCurrentBranch = false,
  final bool moveChanges = false,
  final bool confirmed = false,
  final bool busy = false,
  final String? error,
  final String? warning,
}) {
  WorkspaceRelocationForm copyWith({
    String? branch,
    String? replacementBranch,
    bool? useCurrentBranch,
    bool? moveChanges,
    bool? confirmed,
    bool? busy,
    String? error,
    String? warning,
  }) => WorkspaceRelocationForm(
    relocationId: relocationId,
    branch: branch ?? this.branch,
    replacementBranch: replacementBranch ?? this.replacementBranch,
    useCurrentBranch: useCurrentBranch ?? this.useCurrentBranch,
    moveChanges: moveChanges ?? this.moveChanges,
    confirmed: confirmed ?? this.confirmed,
    busy: busy ?? this.busy,
    error: error,
    warning: warning,
  );
}

@riverpod
class WorkspaceRelocationController extends _$WorkspaceRelocationController {
  @override
  WorkspaceRelocationForm build(String hostId, String workspaceId) =>
      WorkspaceRelocationForm(relocationId: const Uuid().v4());

  void edit({
    String? branch,
    String? replacementBranch,
    bool? useCurrentBranch,
    bool? moveChanges,
  }) {
    if (state.busy) return;
    state = state.copyWith(
      branch: branch,
      replacementBranch: replacementBranch,
      useCurrentBranch: useCurrentBranch,
      moveChanges: useCurrentBranch == true ? true : moveChanges,
      confirmed: false,
    );
  }

  void confirm(bool value) {
    if (!state.busy) state = state.copyWith(confirmed: value);
  }

  Future<bool> submit(WorkspaceSummary workspace) async {
    if (state.busy) return false;
    final draft = state;
    final keepAlive = ref.keepAlive();
    state = state.copyWith(busy: true);
    try {
      if (!draft.confirmed) {
        throw StateError('Confirm the shared checkout impact first.');
      }
      if (workspace.id != workspaceId) {
        throw StateError('The selected task changed.');
      }
      final client = await ref.read(workspaceClientProvider(hostId).future);
      if (client is! WorkspaceRelocationClient ||
          !(client as WorkspaceRelocationClient).supportsWorkspaceRelocation) {
        throw UnsupportedError(
          'Update Alera on this host to relocate workspaces.',
        );
      }
      final relocation = client as WorkspaceRelocationClient;
      if (workspace.isMain) {
        final branch = draft.useCurrentBranch
            ? workspace.branch?.trim() ?? ''
            : draft.branch.trim();
        if (branch.isEmpty || branch == 'HEAD') {
          throw StateError('Choose a branch before Hand Off.');
        }
        if (draft.useCurrentBranch &&
            (draft.replacementBranch.trim().isEmpty || !draft.moveChanges)) {
          throw StateError(
            'Moving the current branch requires an existing replacement branch and all transferable changes.',
          );
        }
        final creation = await relocation.handOffWorkspace(
          workspaceId: workspaceId,
          relocationId: draft.relocationId,
          branch: branch,
          moveChanges: draft.moveChanges,
          sharedImpactConfirmed: true,
          replacementBranch: draft.useCurrentBranch
              ? draft.replacementBranch.trim()
              : null,
        );
        if (creation.hasDeferredSetup) {
          try {
            final terminal = await ref.read(
              terminalClientProvider(hostId).future,
            );
            final result = await launchDeferredWorkspaceSetup(
              terminal,
              creation,
            );
            if (result.setupLaunchError != null) {
              throw StateError(result.setupLaunchError!);
            }
          } on Object catch (error, stack) {
            Logger(
              'WorkspaceRelocationController',
            ).warning('Relocated task setup could not be opened', error, stack);
            if (ref.mounted) {
              state = state.copyWith(
                warning:
                    'The transfer completed, but setup could not be opened: $error',
              );
            }
          }
        }
      } else {
        await relocation.handOnWorkspace(
          workspaceId: workspaceId,
          relocationId: draft.relocationId,
          sharedImpactConfirmed: true,
        );
      }
      return true;
    } on Object catch (error, stack) {
      Logger('WorkspaceRelocationController')
          .warning('Workspace transfer failed', error, stack);
      if (ref.mounted) state = state.copyWith(error: error.toString());
      return false;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          busy: false,
          error: state.error,
          warning: state.warning,
        );
        ref.invalidate(workspaceListControllerProvider(hostId));
      }
      keepAlive.close();
    }
  }
}
