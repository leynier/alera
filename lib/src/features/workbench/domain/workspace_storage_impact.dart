class const WorkspaceStorageImpact({
  required final String workspaceId,
  required final String path,
  required final int sizeBytes,
  required final int entryCount,
  required final DateTime measuredAt,
  required final DateTime lastActivityAt,
  required final bool safeToClean,
  required final List<String> blockers,
});

abstract interface class WorkspaceStorageRuntime {
  Future<WorkspaceStorageImpact> storageImpact({
    required String workspaceId,
    String? activeWorkspaceId,
  });
}
