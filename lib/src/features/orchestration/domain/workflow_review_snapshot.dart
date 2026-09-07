import 'dart:convert';

enum WorkflowHumanDecision { approve, reject, requestChanges }

class WorkflowReviewSnapshot {
  WorkflowReviewSnapshot.fromJson(Map<String, Object?> value)
    : plan = _freezeReviewJson(value['plan'])! as Map<String, Object?>,
      tasks = List<Map<String, Object?>>.unmodifiable(
        (value['tasks']! as List).map(
          (task) => _freezeReviewJson(task)! as Map<String, Object?>,
        ),
      ),
      challengeJson = jsonEncode(value['challenge']) {
    final challenge = jsonDecode(challengeJson) as Map;
    if (challenge['version'] != 1 ||
        challenge['planDigest'] != plan['digest'] ||
        challenge['runId'] is! String ||
        challenge['revision'] is! int ||
        challenge['scope'] is! String ||
        challenge['expiresAt'] is! int ||
        (challenge['revision']! as int) < 1) {
      throw const FormatException('Invalid workflow review snapshot.');
    }
  }

  final Map<String, Object?> plan;
  final List<Map<String, Object?>> tasks;
  // Preserve the rendered challenge independently of mutable RPC maps.
  final String challengeJson;

  Map<String, Object?> get challenge =>
      Map<String, Object?>.from(jsonDecode(challengeJson) as Map);
  String get runId => challenge['runId']! as String;
  int get revision => challenge['revision']! as int;
  String get scope => challenge['scope']! as String;
  DateTime get expiresAt => DateTime.fromMillisecondsSinceEpoch(
    (challenge['expiresAt']! as int) * 1000,
    isUtc: true,
  );
}

Object? _freezeReviewJson(Object? value) => switch (value) {
  Map() => Map<String, Object?>.unmodifiable(
    value.map(
      (key, nested) => MapEntry(key as String, _freezeReviewJson(nested)),
    ),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freezeReviewJson)),
  null || String() || num() || bool() => value,
  _ => throw const FormatException('Invalid workflow review value.'),
};

class WorkflowPendingDecision {
  const WorkflowPendingDecision({
    required this.runId,
    required this.revision,
    required this.document,
  });

  final String runId;
  final int revision;
  final String document;
}
