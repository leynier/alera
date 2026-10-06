import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_providers.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workspace_focus/application/workspace_focus_request_handler.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_focus_providers.g.dart';

final Logger _logger = Logger('WorkspaceFocusRequests');

/// Opens the stream of workspace ids the runtime asks this app to focus
/// (`alera workspace focus`). Every event counts, including a repeat of the
/// previous id, so this is a plain stream rather than a stream provider.
@Riverpod(keepAlive: true)
Stream<String> Function() workspaceFocusRequestSource(Ref ref) {
  final client = ref.watch(runtimeHostClientProvider);
  return () => client.runtimeEvents
      .map(workspaceFocusRequestId)
      .where((id) => id != null)
      .cast<String>();
}

@Riverpod(keepAlive: true)
void workspaceFocusRequestCoordinator(Ref ref) {
  final workbench = _RiverpodWorkspaceFocusWorkbench(ref);
  final handler = WorkspaceFocusRequestHandler(
    windowActivator: ref.watch(agentStatusNotificationWindowActivatorProvider),
    workbench: workbench,
  );
  final subscription = ref.watch(workspaceFocusRequestSourceProvider)().listen((
    workspaceId,
  ) {
    unawaited(
      handler
          .focus(workspaceId)
          .then((selected) {
            if (!selected) {
              _logger.info('focus request for $workspaceId was not applied');
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            _logger.warning(
              'focus request for $workspaceId failed',
              error,
              stackTrace,
            );
          }),
    );
  });
  ref.onDispose(() {
    unawaited(subscription.cancel());
    workbench.dispose();
  });
}

class _RiverpodWorkspaceFocusWorkbench implements WorkspaceFocusWorkbench {
  _RiverpodWorkspaceFocusWorkbench(this._ref) {
    _subscription = _ref.listen<WorkbenchState>(
      workbenchControllerProvider,
      (_, next) => _changes.add(next),
    );
  }

  final Ref _ref;
  final StreamController<WorkbenchState> _changes =
      StreamController<WorkbenchState>.broadcast();
  late final ProviderSubscription<WorkbenchState> _subscription;

  @override
  WorkbenchState get state => _ref.read(workbenchControllerProvider);

  @override
  Stream<WorkbenchState> get stateChanges => _changes.stream;

  @override
  void closeOverlays() {
    _ref.read(runBoardNavigationProvider.notifier).close();
    _ref.read(automationsNavigationProvider.notifier).close();
  }

  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) => _ref
      .read(workbenchControllerProvider.notifier)
      .selectWorkspace(project: project, workspace: workspace);

  void dispose() {
    _subscription.close();
    unawaited(_changes.close());
  }
}
