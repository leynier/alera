import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_panels_controller.g.dart';

enum WorkspacePanelDestination {
  terminal,
  explorer,
  search,
  sourceControl,
  pullRequest,
}

class const WorkspacePanelCapabilities({
  final bool explorer = false,
  final bool search = false,
  final bool sourceControl = false,
  final bool pullRequest = false,
}) {
  bool get hasAny => explorer || search || sourceControl || pullRequest;

  List<WorkspacePanelDestination> get destinations =>
      <WorkspacePanelDestination>[
        WorkspacePanelDestination.terminal,
        if (explorer) WorkspacePanelDestination.explorer,
        if (search) WorkspacePanelDestination.search,
        if (sourceControl) WorkspacePanelDestination.sourceControl,
        if (pullRequest) WorkspacePanelDestination.pullRequest,
      ];
}

@riverpod
class WorkspacePanelCapabilitiesController
    extends _$WorkspacePanelCapabilitiesController {
  @override
  Future<WorkspacePanelCapabilities> build(String hostId) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    if (client case final MobileWorkspacePanelsClient panels) {
      return WorkspacePanelCapabilities(
        explorer: panels.supportsExplorer,
        search: panels.supportsWorkspaceSearch,
        sourceControl: panels.supportsSourceControl,
        pullRequest: panels.supportsPullRequests,
      );
    }
    return const WorkspacePanelCapabilities();
  }
}

@riverpod
class SelectedWorkspacePanelController
    extends _$SelectedWorkspacePanelController {
  @override
  WorkspacePanelDestination build(String hostId, String workspaceId) =>
      WorkspacePanelDestination.terminal;

  void select(WorkspacePanelDestination destination) => state = destination;
}
