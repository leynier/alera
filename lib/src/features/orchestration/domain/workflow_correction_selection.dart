class WorkflowCorrectionSelection {
  WorkflowCorrectionSelection.fromJson(Map<String, Object?> value)
    : runId = value['runId']! as String,
      revision = value['revision']! as int,
      currentRevision = value['currentRevision']! as int,
      status = value['status']! as String,
      reason = value['changeReason'] as String? ?? '',
      planDigest = (value['plan']! as Map)['digest']! as String,
      objective = (value['plan']! as Map)['objective']! as String,
      sourceSha = (value['plan']! as Map)['sourceSha']! as String,
      recipeName =
          (((value['plan']! as Map)['recipe']! as Map)['recipe']!
                  as Map)['name']!
              as String,
      profileNames = List.unmodifiable(
        ((value['plan']! as Map)['profiles']! as Map).values.map(
          (profile) =>
              '${(profile as Map)['name']} (Revision ${profile['revision']})',
        ),
      );
  final String runId;
  final int revision;
  final int currentRevision;
  final String status;
  final String reason;
  final String planDigest;
  final String objective;
  final String sourceSha;
  final String recipeName;
  final List<String> profileNames;

  void requireCurrent(String expectedRun, int expectedRevision) {
    if (runId != expectedRun ||
        revision != expectedRevision ||
        currentRevision != expectedRevision ||
        !['prepared', 'rejected', 'changesRequested'].contains(status)) {
      throw StateError(
        'This revision is no longer open for correction. Return to the run and review its current state.',
      );
    }
  }
}
