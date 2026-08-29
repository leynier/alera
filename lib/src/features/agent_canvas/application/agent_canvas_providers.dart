import 'dart:async';

import 'package:alera/src/features/agent_canvas/domain/agent_canvas.dart';
import 'package:alera/src/features/agent_canvas/infra/runtime_agent_canvas_repository.dart';
import 'package:alera/src/features/workbench/application/retired_workspace_invalidation.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_canvas_providers.g.dart';

@Riverpod(keepAlive: true)
RuntimeAgentCanvasRepository agentCanvasRepository(Ref ref) {
  return RuntimeAgentCanvasRepository(
    ref.watch(runtimeHostClientProvider),
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

@Riverpod(keepAlive: true)
Stream<List<AgentCanvas>> agentCanvases(Ref ref, String workspaceId) {
  invalidateWhenWorkspaceRetired(ref, workspaceId);
  return ref.watch(agentCanvasRepositoryProvider).watch(workspaceId);
}

@Riverpod(keepAlive: true)
class AgentCanvasSelection extends _$AgentCanvasSelection {
  @override
  String? build(String workspaceId) {
    invalidateWhenWorkspaceRetired(ref, workspaceId);
    return null;
  }

  void select(String terminalSessionId) {
    state = terminalSessionId;
  }
}

@Riverpod(keepAlive: true)
Future<Map<String, Object?>> agentCanvasCapabilities(Ref ref) {
  return ref.watch(agentCanvasRepositoryProvider).capabilities();
}

@Riverpod(keepAlive: true)
AgentCanvasRuntimeSync agentCanvasRuntimeSync(Ref ref) {
  final sync = AgentCanvasRuntimeSync(
    ref.watch(runtimeHostClientProvider),
    onDecisionRequest: (workspaceId) {
      final controller = ref.read(workbenchControllerProvider.notifier);
      final activeWorkspace = ref
          .read(workbenchControllerProvider)
          .activeWorkspace;
      if (activeWorkspace?.id != workspaceId) {
        return;
      }
      controller.setContextPanelTab(WorkbenchContextPanelTab.agentCanvas);
      if (!ref
          .read(workbenchControllerProvider)
          .viewPrefs
          .rightSidebarVisible) {
        controller.toggleRightSidebarVisible();
      }
    },
  );
  ref.onDispose(sync.dispose);
  sync.start();
  return sync;
}

class AgentCanvasRuntimeSync {
  AgentCanvasRuntimeSync(this._client, {required this.onDecisionRequest});

  final RuntimeHostClient _client;
  final void Function(String workspaceId) onDecisionRequest;
  StreamSubscription<RuntimeHostEvent>? _subscription;

  void start() {
    _subscription = _client.runtimeEvents.listen((event) {
      if (event.name != 'agentCanvasChanged') {
        return;
      }
      final workspaceId = event.payload['workspaceId'];
      if (event.payload['reason'] == 'decisionRequest' &&
          workspaceId is String &&
          workspaceId.isNotEmpty) {
        onDecisionRequest(workspaceId);
      }
    });
  }

  void dispose() {
    unawaited(_subscription?.cancel());
  }
}
