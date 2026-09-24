/// Which pull-request problems Watch and Fix reacts to. Remembered globally so
/// the next watch starts from the last choice.
class const PullRequestAgentWatchScope({
  this.checks = true,
  this.comments = true,
  this.conflicts = true,
}) {
  /// Failing CI checks.
  final bool checks;

  /// Unresolved review threads from someone other than the pull request author.
  final bool comments;

  /// Merge conflicts with the base branch.
  final bool conflicts;

  bool get isEmpty => !checks && !comments && !conflicts;

  static const PullRequestAgentWatchScope defaults =
      PullRequestAgentWatchScope();

  PullRequestAgentWatchScope copyWith({
    bool? checks,
    bool? comments,
    bool? conflicts,
  }) {
    return PullRequestAgentWatchScope(
      checks: checks ?? this.checks,
      comments: comments ?? this.comments,
      conflicts: conflicts ?? this.conflicts,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'checks': checks,
    'comments': comments,
    'conflicts': conflicts,
  };

  factory fromJson(Map<String, Object?> json) => PullRequestAgentWatchScope(
    checks: json['checks'] as bool? ?? true,
    comments: json['comments'] as bool? ?? true,
    conflicts: json['conflicts'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      other is PullRequestAgentWatchScope &&
      other.checks == checks &&
      other.comments == comments &&
      other.conflicts == conflicts;

  @override
  int get hashCode => Object.hash(checks, comments, conflicts);
}
