/// Short, log-free prompt for failed pull request checks.
///
/// Check names, logs, and payloads stay out of the prompt so the agent looks
/// them up from the workspace instead of inheriting stale CI output.
String pullRequestFailedChecksPrompt(int reviewNumber) {
  return 'Pull request #$reviewNumber checks failed. Investigate the failing '
      'checks and fix them.';
}

String pullRequestAgentWatchPrompt(int reviewNumber) {
  return pullRequestFailedChecksPrompt(reviewNumber);
}
