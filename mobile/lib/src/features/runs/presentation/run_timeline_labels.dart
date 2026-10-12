/// Sentence case labels for `runs.timeline` rows, matching the desktop
/// timeline.
String runEventLabel(String kind) => switch (kind) {
  'created' => 'Run created',
  'coordinatorStarted' => 'Coordinator started',
  'planProposed' => 'Plan proposed',
  'planApproved' => 'Plan approved',
  'planRejected' => 'Plan rejected',
  'changesRequested' => 'Changes requested',
  'taskCreated' => 'Task created',
  'attemptPrepared' => 'Attempt prepared',
  'dispatched' => 'Dispatched',
  'accepted' => 'Accepted',
  'escalation' => 'Escalation',
  'taskCompleted' => 'Completed',
  'taskFailed' => 'Failed',
  'taskStalled' => 'Stalled',
  'taskCancelled' => 'Task cancelled',
  'gateOpened' => 'Gate opened',
  'gateResolved' => 'Gate resolved',
  'integrationStarted' => 'Integration started',
  'integrated' => 'Integrated',
  'conflict' => 'Conflict',
  'attention' => 'Needs attention',
  'retried' => 'Retried',
  'paused' => 'Paused',
  'resumed' => 'Resumed',
  'cancelled' => 'Run cancelled',
  'completed' => 'Run completed',
  'failed' => 'Run failed',
  'cleanupPrepared' => 'Cleanup prepared',
  'cleanupApplied' => 'Cleanup applied',
  'cleanupAbandoned' => 'Cleanup abandoned',
  final other => _sentence(other),
};

/// `merge_ready` -> `Merge ready`; a question or decision gate is a question.
String runMessageTypeLabel(String? type) => switch (type) {
  null || '' => 'Message',
  'question' || 'decision_gate' => 'Question',
  final other => _sentence(other),
};

String _sentence(String raw) {
  final words = raw
      .replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .toLowerCase()
      .trim();
  return words.isEmpty ? raw : '${words[0].toUpperCase()}${words.substring(1)}';
}
