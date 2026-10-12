import 'package:alera_automations/alera_automations.dart';
import 'package:test/test.dart';

AutomationRecord _record(JsonMap extra) =>
    AutomationRecord.fromJson(<String, Object?>{
      'id': 'a1',
      'target': <String, Object?>{
        'worktree': <String, Object?>{
          'projectId': 'p1',
          'sourceBranch': 'main',
          'agentProfileId': 'codex',
        },
      },
      ...extra,
    });

void main() {
  test('an absent or unknown policy reads as new each run', () {
    expect(_record(const {}).reusePolicy, AutomationReusePolicy.newEachRun);
    expect(
      AutomationReusePolicy.parse('somethingNew'),
      AutomationReusePolicy.newEachRun,
    );
    expect(
      _record(const {'reusePolicy': 'reuseConversation'}).reusePolicy,
      AutomationReusePolicy.reuseConversation,
    );
    expect(automationReuseCapability, 'automationReuseV1');
  });

  test('each target type offers only the policies the runtime accepts', () {
    expect(
      applicableReusePolicies(AutomationTargetType.worktree),
      AutomationReusePolicy.values,
    );
    expect(
      applicableReusePolicies(AutomationTargetType.projectCheckout),
      AutomationReusePolicy.values,
    );
    expect(applicableReusePolicies(AutomationTargetType.freshTab), <Object>[
      AutomationReusePolicy.newEachRun,
      AutomationReusePolicy.reuseConversation,
    ]);
    expect(applicableReusePolicies(AutomationTargetType.existingTab), <Object>[
      AutomationReusePolicy.reuseConversation,
    ]);
    expect(
      automationReusePolicyIsFixed(AutomationTargetType.existingTab),
      isTrue,
    );
    expect(
      automationReusePolicyIsFixed(AutomationTargetType.freshTab),
      isFalse,
    );
  });

  test('the bound target and its summary come from the catalog item', () {
    final bound = _record(<String, Object?>{
      'reusePolicy': 'reuseConversation',
      'boundTarget': <String, Object?>{
        'workspaceId': 'ws-1',
        'tabId': 'tab-1',
        'conversationId': 'conv-1',
        'agentProfileId': 'codex',
        'boundRunId': 'run-1',
        'boundAt': '2026-10-01T09:00:00Z',
        'lastRunId': 'run-3',
        'lastVerifiedAt': '2026-10-03T09:00:00Z',
      },
      'boundTargetSummary': 'Alera / main · Codex',
    });
    final target = bound.boundTarget!;
    expect(bound.isBound, isTrue);
    expect(target.workspaceId, 'ws-1');
    expect(target.tabId, 'tab-1');
    expect(target.hasTab, isTrue);
    expect(target.conversationId, 'conv-1');
    expect(target.boundRunId, 'run-1');
    expect(target.boundAt, DateTime.utc(2026, 10, 1, 9));
    expect(target.lastRunId, 'run-3');
    expect(bound.boundTargetSummary, 'Alera / main · Codex');

    final unbound = _record(const <String, Object?>{
      'boundTarget': null,
      'boundTargetSummary': null,
    });
    expect(unbound.boundTarget, isNull);
    expect(unbound.isBound, isFalse);
    expect(unbound.boundTargetSummary, isNull);
  });

  test('runs say how they reused a target', () {
    AutomationRunRecord run(Object? reuse) => AutomationRunRecord.fromJson(
      <String, Object?>{'id': 'r1', 'status': 'dispatched', 'reuse': reuse},
    );
    expect(run(null).reuse, isNull);
    expect(run('bound').reuse, AutomationRunReuse.bound);
    expect(
      run('resumedConversation').reuse,
      AutomationRunReuse.resumedConversation,
    );
    expect(run('later').reuse, isNull);
  });

  test('a parked run names what it waits for', () {
    AutomationRunRecord parked(String code) =>
        AutomationRunRecord.fromJson(<String, Object?>{
          'id': 'r1',
          'status': 'pending',
          'recovery': <String, Object?>{'status': 'waiting', 'code': code},
        });
    final conversation = automationRunStatusLabel(
      parked('waitingForBoundConversation'),
    );
    expect(conversation.label, 'Waiting For Bound Conversation');
    expect(conversation.inProgress, isTrue);
    expect(
      automationRunStatusLabel(parked('waitingForRemoteHost')).label,
      'Waiting For Remote Host',
    );
    expect(parked('x').recovery.status, AutomationRecoveryStatus.waiting);
    expect(parked('x').recovery.isActive, isTrue);
  });

  test('binding audits and reuse launches have readable labels', () {
    expect(
      automationActivityLabel(const {'action': 'targetBound'}),
      'Bound to a target',
    );
    expect(
      automationActivityLabel(const {'action': 'boundTabReleased'}),
      'Released the bound tab',
    );
    expect(
      automationActivityLabel(const {
        'action': 'targetUnbound',
        'details': {'reason': 'workspaceGone'},
      }),
      'Unbound because the workspace was removed',
    );
    expect(
      automationActivityLabel(const {
        'action': 'targetUnbound',
        'details': {'reason': 'unbound'},
      }),
      'Unbound',
    );
    expect(automationLaunchKindLabel('reusePaste'), 'Continued Conversation');
    expect(
      automationLaunchKindLabel('reuseRelaunch'),
      'Relaunched Conversation',
    );
    expect(automationLaunchKindLabel(null), 'Started');
    expect(
      automationActorLabel(const {'kind': 'localCli', 'label': 'me'}),
      'CLI (me)',
    );
  });

  test('a run status maps to one compact tone', () {
    expect(automationRunStatusTone('success'), AutomationTone.success);
    expect(automationRunStatusTone('timeout'), AutomationTone.error);
    expect(automationRunStatusTone('waitingForUser'), AutomationTone.warning);
    expect(automationRunStatusTone('dispatched'), AutomationTone.info);
    expect(automationRunStatusTone('cancelled'), AutomationTone.neutral);
  });

  test('error messages lose their type prefix and unwrap readiness', () {
    expect(automationErrorMessage(Exception('Host offline')), 'Host offline');
    expect(automationErrorMessage(StateError('Not found')), 'Not found');
    expect(automationErrorMessage('  '), 'Something went wrong. Try again.');
    const issue = AutomationReadinessIssue(
      code: 'missingProfile',
      message: 'Choose an agent profile.',
      severity: AutomationIssueSeverity.error,
    );
    expect(
      automationErrorMessage(
        const AutomationReadinessException(
          AutomationReadiness(ready: false, issues: [issue]),
        ),
      ),
      'Choose an agent profile.',
    );
  });
}
