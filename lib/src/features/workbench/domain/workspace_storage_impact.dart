class WorkspaceStorageImpact {
  const WorkspaceStorageImpact({
    required this.workspaceId,
    required this.path,
    required this.sizeBytes,
    required this.entryCount,
    required this.measuredAt,
    required this.lastActivityAt,
    required this.safeToClean,
    required this.blockers,
  });

  final String workspaceId;
  final String path;
  final int sizeBytes;
  final int entryCount;
  final DateTime measuredAt;
  final DateTime lastActivityAt;
  final bool safeToClean;
  final List<String> blockers;
}

abstract interface class WorkspaceStorageRuntime {
  Future<WorkspaceStorageImpact> storageImpact({
    required String workspaceId,
    String? activeWorkspaceId,
  });
}
