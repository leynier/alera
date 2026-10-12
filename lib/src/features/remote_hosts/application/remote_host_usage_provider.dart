import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'remote_host_usage_provider.g.dart';

/// How much of the workbench lives on one host.
class const RemoteHostUsage({
  final int projectCount = 0,
  final int workspaceCount = 0,
}) {
  bool get isEmpty => projectCount == 0 && workspaceCount == 0;

  /// `2 projects · 5 workspaces`, omitting a zero count, or `No projects`.
  String get summary {
    final parts = <String>[
      if (projectCount > 0) _count(projectCount, 'project'),
      if (workspaceCount > 0) _count(workspaceCount, 'workspace'),
    ];
    return parts.isEmpty ? 'No projects' : parts.join(' · ');
  }
}

/// Counts projects and workspaces per remote host id. A project counts on
/// every host it has a checkout on, including its primary host.
Map<String, RemoteHostUsage> remoteHostUsageFrom({
  required Iterable<Project> projects,
  required Iterable<Workspace> workspaces,
}) {
  final projectCounts = <String, int>{};
  for (final project in projects) {
    final hosts = <String>{
      ?normalizedRemoteHostId(project.primaryHostId),
      for (final checkout in project.checkouts)
        ?normalizedRemoteHostId(checkout.hostId),
    };
    for (final host in hosts) {
      projectCounts[host] = (projectCounts[host] ?? 0) + 1;
    }
  }
  final workspaceCounts = <String, int>{};
  for (final workspace in workspaces) {
    if (normalizedRemoteHostId(workspace.hostId) case final host?) {
      workspaceCounts[host] = (workspaceCounts[host] ?? 0) + 1;
    }
  }
  return Map<String, RemoteHostUsage>.unmodifiableOf(<String, RemoteHostUsage>{
    for (final host in <String>{...projectCounts.keys, ...workspaceCounts.keys})
      host: RemoteHostUsage(
        projectCount: projectCounts[host] ?? 0,
        workspaceCount: workspaceCounts[host] ?? 0,
      ),
  });
}

@riverpod
Map<String, RemoteHostUsage> remoteHostUsage(Ref ref) {
  final projects = ref.watch(projectListProvider).value ?? const <Project>[];
  final workspacesByProject = ref.watch(
    workbenchControllerProvider.select((state) => state.workspacesByProject),
  );
  return remoteHostUsageFrom(
    projects: projects,
    workspaces: workspacesByProject.values.expand((list) => list),
  );
}

String _count(int count, String noun) =>
    count == 1 ? '1 $noun' : '$count ${noun}s';
