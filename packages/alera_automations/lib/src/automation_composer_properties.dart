import 'package:alera_automations/src/automation_draft.dart';
import 'package:alera_automations/src/automation_field_bounds.dart';
import 'package:alera_automations/src/automation_models.dart';
import 'package:alera_automations/src/automation_readiness.dart';

/// The properties a prompt-first editor shows as separate controls, so a
/// local problem or a readiness issue can mark the one it is about.
enum AutomationComposerProperty {
  prompt,
  schedule,
  destination,
  agent,
  reuse,
  options,
}

const Set<String> _profileIssueCodes = <String>{
  'missingProfile',
  'invalidProfile',
  'profileNotLaunchable',
};

/// The property a runtime readiness issue names. Profile problems arrive
/// under the `target` field, so they are told apart by code; a conversation
/// target has no agent control, so its profile problems mark the destination.
AutomationComposerProperty? automationIssueProperty(
  AutomationReadinessIssue issue, {
  AutomationTargetType? targetType,
}) {
  if (_profileIssueCodes.contains(issue.code)) {
    return targetType == AutomationTargetType.existingTab
        ? AutomationComposerProperty.destination
        : AutomationComposerProperty.agent;
  }
  return switch (issue.field) {
    'promptTemplate' => AutomationComposerProperty.prompt,
    'schedule' => AutomationComposerProperty.schedule,
    'target' ||
    'projectId' ||
    'originWorkspaceId' => AutomationComposerProperty.destination,
    'reusePolicy' => AutomationComposerProperty.reuse,
    'cleanupPolicy' => AutomationComposerProperty.options,
    _ => null,
  };
}

/// What a composer needs to know about a draft beyond what it sends.
extension AutomationComposerDraft on AutomationDraft {
  /// Null once a destination is chosen and complete. The agent profile is
  /// reported separately by [agentError].
  String? get destinationError {
    if (targetType == null) return 'Choose where the automation runs.';
    for (final field in requiredTargetFields) {
      if (field == AutomationDraftField.agentProfileId) continue;
      if ((targetFields[field] ?? '').isEmpty) {
        return 'Complete the destination.';
      }
    }
    return null;
  }

  String? get agentError =>
      requiredTargetFields.contains(AutomationDraftField.agentProfileId) &&
          (field(AutomationDraftField.agentProfileId) ?? '').isEmpty
      ? 'Choose an agent profile.'
      : null;

  /// Problems the user can fix before the runtime is asked, by property.
  Map<AutomationComposerProperty, String> get localProblems =>
      <AutomationComposerProperty, String>{
        AutomationComposerProperty.prompt: ?whatError,
        AutomationComposerProperty.schedule: ?whenError,
        AutomationComposerProperty.destination: ?destinationError,
        AutomationComposerProperty.agent: ?agentError,
        if (numberErrors.isNotEmpty)
          AutomationComposerProperty.options: 'Fix the highlighted options.',
      };

  /// Start, end, run limit and missed schedules only bound a recurring
  /// schedule.
  bool get offersScheduleLimits => !schedule.isOneTime;

  /// Name template, section and tags apply to the workspaces runs create.
  bool get offersWorkspaceOptions => targetType?.createsWorkspace ?? false;

  /// Setup scripts only run in a new worktree.
  bool get offersWorkspaceSetup => targetType == AutomationTargetType.worktree;

  /// A reused workspace must outlive the run, so cleanup only applies when
  /// every run gets its own.
  bool get offersCleanup => offersWorkspaceOptions && !reusePolicy.reuses;

  /// How many applicable options differ from their defaults, for the badge on
  /// the control that reveals them.
  int get customizedOptionCount {
    bool changed(AutomationNumericField field) =>
        number(field).trim() != '${field.defaultValue}';
    final precheck = precheckCommand.trim().isNotEmpty;
    return <bool>[
      if (offersScheduleLimits) ...<bool>[
        startAt.trim().isNotEmpty,
        endAt.trim().isNotEmpty,
        number(AutomationNumericField.maxScheduledRuns).trim().isNotEmpty,
        misfirePolicy != 'skip',
      ],
      overlapPolicy != 'skip',
      changed(AutomationNumericField.inactivityTimeoutSeconds),
      changed(AutomationNumericField.retryMaxAttempts),
      precheck,
      precheck && changed(AutomationNumericField.precheckTimeoutSeconds),
      if (offersWorkspaceOptions) ...<bool>[
        nameTemplate.trim() != automationDefaultNameTemplate,
        workspaceSectionId != null,
        workspaceTagIds.isNotEmpty,
      ],
      if (offersWorkspaceSetup) setupPolicy != 'wait',
      if (offersCleanup) cleanupPolicy != 'preserve',
      notifyOnSuccess,
    ].where((value) => value).length;
  }
}
