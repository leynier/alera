/// The run a terminal belongs to, from the host-owned tab payload keys the
/// runtime stamps on run coordinator and worker tabs (`runId`, and
/// `runTaskId` for workers). A tab outside a run, or from an older host,
/// has neither.
class RunTabIdentity {
  const RunTabIdentity({required this.runId, this.taskId});

  final String runId;
  final String? taskId;

  static RunTabIdentity? fromPayload(Map<String, Object?> payload) {
    final runId = _text(payload['runId']);
    if (runId == null) return null;
    return RunTabIdentity(runId: runId, taskId: _text(payload['runTaskId']));
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;
}
