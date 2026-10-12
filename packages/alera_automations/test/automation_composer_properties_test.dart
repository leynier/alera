import 'package:alera_automations/alera_automations.dart';
import 'package:test/test.dart';

AutomationReadinessIssue _issue(String code, String field) =>
    AutomationReadinessIssue(
      code: code,
      message: code,
      severity: AutomationIssueSeverity.error,
      field: field,
    );

AutomationDraft _freshTab() =>
    const AutomationDraft(promptTemplate: 'Review')
        .withTargetType(AutomationTargetType.freshTab)
        .withTargetField(.workspaceId, 'ws-1')
        .withTargetField(.agentProfileId, 'codex');

void main() {
  test('readiness issues point at the control they are about', () {
    expect(
      automationIssueProperty(_issue('noFutureOccurrences', 'schedule')),
      AutomationComposerProperty.schedule,
    );
    expect(
      automationIssueProperty(_issue('targetUnavailable', 'target')),
      AutomationComposerProperty.destination,
    );
    expect(
      automationIssueProperty(_issue('profileNotLaunchable', 'target')),
      AutomationComposerProperty.agent,
    );
    expect(
      automationIssueProperty(
        _issue('missingProfile', 'target'),
        targetType: AutomationTargetType.existingTab,
      ),
      AutomationComposerProperty.destination,
    );
    expect(
      automationIssueProperty(_issue('invalidDefinition', 'cleanupPolicy')),
      AutomationComposerProperty.options,
    );
    expect(
      automationIssueProperty(_issue('invalidDefinition', 'reusePolicy')),
      AutomationComposerProperty.reuse,
    );
    expect(
      automationIssueProperty(_issue('invalidDefinition', 'automation')),
      isNull,
    );
  });

  test('local problems separate the destination from the agent', () {
    const empty = AutomationDraft();
    expect(empty.localProblems.keys, <AutomationComposerProperty>[
      .prompt,
      .destination,
    ]);
    final noProfile = const AutomationDraft(promptTemplate: 'Review')
        .withTargetType(AutomationTargetType.freshTab)
        .withTargetField(.workspaceId, 'ws-1');
    expect(noProfile.destinationError, isNull);
    expect(noProfile.agentError, 'Choose an agent profile.');
    expect(_freshTab().localProblems, isEmpty);
    final conversation = const AutomationDraft(promptTemplate: 'Review')
        .withTargetType(AutomationTargetType.existingTab);
    expect(conversation.agentError, isNull);
    expect(conversation.destinationError, 'Complete the destination.');
  });

  test('options are offered only where they apply', () {
    final freshTab = _freshTab();
    expect(freshTab.offersWorkspaceOptions, isFalse);
    expect(freshTab.offersWorkspaceSetup, isFalse);
    final worktree = freshTab.withTargetType(AutomationTargetType.worktree);
    expect(worktree.offersWorkspaceSetup, isTrue);
    expect(worktree.offersCleanup, isTrue);
    expect(
      worktree
          .copyWith(reusePolicy: AutomationReusePolicy.reuseWorkspace)
          .offersCleanup,
      isFalse,
    );
    expect(
      freshTab
          .copyWith(schedule: const AutomationSchedulePreset(kind: .once))
          .offersScheduleLimits,
      isFalse,
    );
  });

  test('the options count only covers changed, applicable options', () {
    expect(_freshTab().customizedOptionCount, 0);
    final changed = _freshTab().copyWith(
      notifyOnSuccess: true,
      overlapPolicy: 'queue',
      setupPolicy: 'skip',
      numbers: <AutomationNumericField, String>{
        .inactivityTimeoutSeconds: '600',
      },
    );
    expect(changed.customizedOptionCount, 3);
    final reloaded = AutomationDraft.fromRecord(
      AutomationRecord.fromJson(<String, Object?>{
        'id': 'a',
        'name': 'A',
        'promptTemplate': 'Fix',
        'schedule': <String, Object?>{
          'recurring': <String, Object?>{'cron': '0 9 * * *'},
        },
        'target': <String, Object?>{
          'freshTab': <String, Object?>{
            'workspaceId': 'ws-1',
            'agentProfileId': 'codex',
          },
        },
      }),
    );
    expect(reloaded.customizedOptionCount, 0);
  });
}
