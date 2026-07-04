/// Persists per-workspace last-activity timestamps used as the recency
/// fallback for the Agent Activity sort across app restarts.
abstract interface class WorkspaceActivityRepository {
  Future<Map<String, DateTime>> loadAll();
  Future<void> upsertAll(Map<String, DateTime> entries);
  Future<void> remove(String workspaceId);
}
