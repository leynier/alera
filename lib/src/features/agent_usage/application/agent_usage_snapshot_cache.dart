abstract interface class AgentUsageSnapshotCache {
  Map<String, Object?>? peek({required String hostId, required int days});

  Future<Map<String, Object?>?> read({
    required String hostId,
    required int days,
  });

  Future<void> write({
    required String hostId,
    required int days,
    required Map<String, Object?> snapshot,
  });
}
