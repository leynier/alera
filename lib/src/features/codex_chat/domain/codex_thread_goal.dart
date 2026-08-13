part of 'codex_chat_models.dart';

enum CodexThreadGoalStatus {
  active,
  paused,
  blocked,
  usageLimited,
  budgetLimited,
  complete;

  static CodexThreadGoalStatus fromWire(Object? value) => switch (value) {
    'paused' => paused,
    'blocked' => blocked,
    'usageLimited' => usageLimited,
    'budgetLimited' => budgetLimited,
    'complete' => complete,
    _ => active,
  };

  String get wireName => switch (this) {
    active => 'active',
    paused => 'paused',
    blocked => 'blocked',
    usageLimited => 'usageLimited',
    budgetLimited => 'budgetLimited',
    complete => 'complete',
  };

  bool get canPause => this == active;
  bool get canResume =>
      this == paused || this == blocked || this == usageLimited;
}

@immutable
class CodexThreadGoal {
  const CodexThreadGoal({
    required this.threadId,
    required this.objective,
    required this.status,
    required this.tokensUsed,
    required this.timeUsedSeconds,
    required this.createdAt,
    required this.updatedAt,
    this.tokenBudget,
  });

  factory CodexThreadGoal.fromJson(Object? value) {
    final json = _map(value);
    return CodexThreadGoal(
      threadId: _string(json['threadId']) ?? '',
      objective: _string(json['objective']) ?? '',
      status: CodexThreadGoalStatus.fromWire(json['status']),
      tokenBudget: _int(json['tokenBudget']),
      tokensUsed: _int(json['tokensUsed']) ?? 0,
      timeUsedSeconds: _int(json['timeUsedSeconds']) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (_int(json['createdAt']) ?? 0) * 1000,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (_int(json['updatedAt']) ?? 0) * 1000,
        isUtc: true,
      ),
    );
  }

  final String threadId;
  final String objective;
  final CodexThreadGoalStatus status;
  final int? tokenBudget;
  final int tokensUsed;
  final int timeUsedSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'threadId': threadId,
    'objective': objective,
    'status': status.wireName,
    'tokenBudget': tokenBudget,
    'tokensUsed': tokensUsed,
    'timeUsedSeconds': timeUsedSeconds,
    'createdAt': createdAt.millisecondsSinceEpoch ~/ 1000,
    'updatedAt': updatedAt.millisecondsSinceEpoch ~/ 1000,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodexThreadGoal &&
          threadId == other.threadId &&
          objective == other.objective &&
          status == other.status &&
          tokenBudget == other.tokenBudget &&
          tokensUsed == other.tokensUsed &&
          timeUsedSeconds == other.timeUsedSeconds &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    threadId,
    objective,
    status,
    tokenBudget,
    tokensUsed,
    timeUsedSeconds,
    createdAt,
    updatedAt,
  );
}
