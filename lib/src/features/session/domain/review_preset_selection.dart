enum ReviewPresetSelection {
  baseBranch,
  uncommittedChanges,
  commit,
  customInstructions,
}

extension ReviewPresetSelectionX on ReviewPresetSelection {
  String get title {
    switch (this) {
      case ReviewPresetSelection.baseBranch:
        return 'Review against a base branch';
      case ReviewPresetSelection.uncommittedChanges:
        return 'Review uncommitted changes';
      case ReviewPresetSelection.commit:
        return 'Review a commit';
      case ReviewPresetSelection.customInstructions:
        return 'Custom review instructions';
    }
  }

  String get description {
    switch (this) {
      case ReviewPresetSelection.baseBranch:
        return 'Choose a branch to compare against before starting the review.';
      case ReviewPresetSelection.uncommittedChanges:
        return 'Review the current working tree immediately.';
      case ReviewPresetSelection.commit:
        return 'Enter a commit SHA or ref to review a specific commit.';
      case ReviewPresetSelection.customInstructions:
        return 'Write custom review instructions before starting.';
    }
  }
}
