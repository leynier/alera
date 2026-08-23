import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_runtime_status.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_selection_order.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:logging/logging.dart';

part 'host_dashboard_controller.g.dart';

/// How many projects get branch details eagerly loaded for the dashboard.
const int dashboardProjectBranchLimit = 3;

class HostDashboardData {
  const HostDashboardData({
    required this.status,
    required this.projects,
    required this.workspaces,
    required this.branchesByProject,
  });

  final MobileRuntimeStatus status;
  final List<ProjectSummary> projects;
  final List<WorkspaceSummary> workspaces;
  final Map<String, ProjectBranches> branchesByProject;
}

@riverpod
Future<HostDashboardData> hostDashboardData(Ref ref, String hostId) async {
  final connectionProvider = hostConnectionControllerProvider(hostId);
  var client = await ref.watch(connectionProvider.future);
  if (!client.isConnectionUsable) {
    await ref.read(connectionProvider.notifier).reconnectNow();
    client = await ref.read(connectionProvider.future);
  }
  final status = await client.mobileStatus();
  final projects = sortProjectsForSelection(await client.listProjects());
  final workspaces = await client.listWorkspaces();
  final branchesByProject = <String, ProjectBranches>{};
  for (final project in projects.take(dashboardProjectBranchLimit)) {
    try {
      branchesByProject[project.id] = await client.listBranches(project.id);
    } on Object catch (error, stackTrace) {
      // Branch discovery can fail for invalid or moved repos; keep the
      // dashboard usable and surface the project/workspace state. The project
      // then shows no branches, which is worth being able to explain.
      Logger('HostDashboardController').warning(
        'could not list branches for project ${project.id}',
        error,
        stackTrace,
      );
    }
  }
  return HostDashboardData(
    status: status,
    projects: projects,
    workspaces: workspaces,
    branchesByProject: branchesByProject,
  );
}
