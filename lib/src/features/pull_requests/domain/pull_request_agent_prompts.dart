import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';

/// Short, log-free prompt for failed pull request checks.
///
/// Check names, logs, and payloads stay out of the prompt so the agent looks
/// them up from the workspace instead of inheriting stale CI output.
String pullRequestFailedChecksPrompt(int reviewNumber) {
  return 'Pull request #$reviewNumber checks failed. Please fix them.';
}

/// One prompt naming every pending problem, still free of comment bodies and
/// CI logs so the agent reads the current threads and conflicts itself.
///
/// The prompt may reach a shell as a launch argument, so it avoids backticks
/// and other characters a shell would expand.
String pullRequestAgentWatchPrompt({
  required int reviewNumber,
  required PullRequestAgentWatchConcerns concerns,
  String? baseBranch,
}) {
  final threadCount = concerns.threads.length;
  if (concerns.isEmpty) {
    return 'Please check pull request #$reviewNumber and fix anything that '
        'blocks it.';
  }
  if (concerns.checksFailed && !concerns.conflict && threadCount == 0) {
    return pullRequestFailedChecksPrompt(reviewNumber);
  }
  final base = baseBranch?.trim();
  final problems = <String>[
    if (concerns.conflict)
      base == null || base.isEmpty
          ? 'merge conflicts with its base branch'
          : 'merge conflicts with $base',
    if (concerns.checksFailed) 'failing checks',
    if (threadCount > 0)
      threadCount == 1
          ? '1 unresolved review thread'
          : '$threadCount unresolved review threads',
  ];
  final requests = <String>[
    if (concerns.conflict) 'resolve the conflicts',
    if (concerns.checksFailed) 'fix the checks',
    if (threadCount > 0) 'address the review comments',
  ];
  final buffer = StringBuffer(
    'Pull request #$reviewNumber has ${_joinPhrases(problems)}. '
    'Please ${_joinPhrases(requests)}.',
  );
  if (threadCount > 0) {
    buffer.write(' Resolve each review thread once its fix is pushed.');
  }
  return buffer.toString();
}

String _joinPhrases(List<String> phrases) {
  return switch (phrases.length) {
    0 => '',
    1 => phrases.single,
    2 => '${phrases.first} and ${phrases.last}',
    _ =>
      '${phrases.sublist(0, phrases.length - 1).join(', ')}, '
          'and ${phrases.last}',
  };
}
