import 'package:dart_mappable/dart_mappable.dart';

part 'pull_request_agent_watch_scope.mapper.dart';

/// Which pull-request problems Watch and Fix reacts to. Remembered globally so
/// the next watch starts from the last choice.
@MappableClass()
class const PullRequestAgentWatchScope({
  this.checks = true,
  this.comments = true,
  this.conflicts = true,
}) with PullRequestAgentWatchScopeMappable {
  /// Failing CI checks.
  final bool checks;

  /// Unresolved review threads from someone other than the pull request author.
  final bool comments;

  /// Merge conflicts with the base branch.
  final bool conflicts;

  bool get isEmpty => !checks && !comments && !conflicts;

  static const PullRequestAgentWatchScope defaults =
      PullRequestAgentWatchScope();

  factory fromJson(Map<String, Object?> json) =>
      PullRequestAgentWatchScopeMapper.fromMap(Map<String, dynamic>.from(json));
}
