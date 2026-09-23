class const WorkspaceRemovalDependency({
  required final String id,
  required final String name,
  required final int activeRuns,
  required final bool requiresPause,
}) {
  factory fromJson(Map<String, Object?> json) => WorkspaceRemovalDependency(
    id: json['id'] as String,
    name: json['name'] as String,
    activeRuns: (json['activeRuns'] as num).toInt(),
    requiresPause: json['requiresPause'] == true,
  );
}

abstract interface class WorkspaceRemovalDependencyRuntime {
  Future<List<WorkspaceRemovalDependency>> removalDependencies(
    String workspaceId,
  );
  Future<void> pauseRemovalDependencies(
    String workspaceId,
    List<WorkspaceRemovalDependency> approved,
  );
}

abstract interface class ProjectRemovalDependencyRuntime {
  Future<List<WorkspaceRemovalDependency>> projectRemovalDependencies(
    String projectId,
  );
  Future<void> pauseProjectRemovalDependencies(
    String projectId,
    List<WorkspaceRemovalDependency> approved,
  );
}
