part of 'mobile_codex_chat_screen.dart';

enum _MobileCodexReviewTarget {
  uncommittedChanges,
  baseBranch,
  commit,
  custom;

  String get wireValue => switch (this) {
    uncommittedChanges => 'uncommittedChanges',
    baseBranch => 'baseBranch',
    commit => 'commit',
    custom => 'custom',
  };

  String get label => switch (this) {
    uncommittedChanges => 'Uncommitted Changes',
    baseBranch => 'Base Branch',
    commit => 'Commit',
    custom => 'Custom Instructions',
  };

  String get description => switch (this) {
    uncommittedChanges =>
      'Review staged, unstaged, and untracked changes in this workspace.',
    baseBranch =>
      'Review the current branch against the merge base of another branch.',
    commit => 'Review one commit by its SHA.',
    custom => 'Describe the exact scope and focus for the reviewer.',
  };
}

enum _MobileCodexReviewDelivery {
  inline,
  detached;

  String get wireValue => name;

  String get label => switch (this) {
    inline => 'Inline',
    detached => 'Detached',
  };

  String get description => switch (this) {
    inline => 'Run the review in this conversation.',
    detached => 'Fork a separate review thread from this conversation.',
  };
}

final class const _MobileCodexReviewSelection({
  required final _MobileCodexReviewTarget target,
  required final _MobileCodexReviewDelivery delivery,
  final String? argument,
  final String? commitTitle,
});
