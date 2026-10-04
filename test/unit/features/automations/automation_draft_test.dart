import 'package:alera/src/features/automations/application/automation_target_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_draft.dart';
import 'package:alera/src/features/automations/domain/automation_field_bounds.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/automation_test_harness.dart';

void main() {
  test('a new draft has no target type and cannot continue past Where', () {
    const draft = AutomationDraft(
      promptTemplate: 'Review',
      originWorkspaceId: 'ws-1',
    );
    expect(draft.targetType, isNull);
    expect(draft.whereError, 'Choose where the automation runs.');
    expect(draft.toDefinition().containsKey('target'), isFalse);
  });

  test('creating is active unless saved as a draft explicitly', () {
    final draft = const AutomationDraft(promptTemplate: 'Review')
        .withTargetType(AutomationTargetType.freshTab)
        .withTargetField(.workspaceId, 'ws-1')
        .withTargetField(.agentProfileId, 'codex');
    expect(draft.whereError, isNull);
    final active = draft.toDefinition();
    expect(active.containsKey('state'), isFalse);
    expect(active['target'], <String, Object?>{
      'freshTab': <String, Object?>{
        'workspaceId': 'ws-1',
        'agentProfileId': 'codex',
      },
    });
    expect(active['misfirePolicy'], 'skip');
    expect(draft.toDefinition(draft: true)['state'], 'draft');
  });

  test('numbers use the runtime bounds and are never clamped', () {
    final draft = const AutomationDraft().copyWith(
      numbers: <AutomationNumericField, String>{
        .circuitFailureThreshold: '11',
        .circuitOpenSeconds: '604800',
        .precheckTimeoutSeconds: '901',
        .inactivityTimeoutSeconds: '100',
        .heartbeatIntervalSeconds: '101',
        .retryMaxAttempts: '0',
        .misfireGraceSeconds: '0',
      },
    );
    final errors = draft.numberErrors;
    expect(
      errors.keys,
      containsAll(<AutomationNumericField>[
        .circuitFailureThreshold,
        .precheckTimeoutSeconds,
        .heartbeatIntervalSeconds,
        .retryMaxAttempts,
      ]),
    );
    expect(
      errors.containsKey(AutomationNumericField.circuitOpenSeconds),
      isFalse,
    );
    expect(
      errors.containsKey(AutomationNumericField.misfireGraceSeconds),
      isFalse,
    );
    expect(draft.toDefinition()['circuitFailureThreshold'], 11);
  });

  test('choosing a target type only fills unambiguous context', () {
    final context = automationTestContext();
    const request = AutomationAuthoringRequest(originWorkspaceId: 'ws-1');
    final draft = chooseAutomationTargetType(
      const AutomationDraft(originWorkspaceId: 'ws-1'),
      AutomationTargetType.freshTab,
      context,
      request,
    );
    expect(draft.targetType, AutomationTargetType.freshTab);
    expect(draft.field(.workspaceId), 'ws-1');
    expect(draft.field(.agentProfileId), 'codex');
    expect(draft.fromContext, {
      AutomationDraftField.workspaceId,
      AutomationDraftField.agentProfileId,
    });
    final edited = draft.withTargetField(.workspaceId, 'ws-2');
    expect(edited.fromContext, {AutomationDraftField.agentProfileId});
  });

  test('switching target type drops the previous type fields', () {
    final context = automationTestContext();
    final freshTab = chooseAutomationTargetType(
      const AutomationDraft(),
      AutomationTargetType.freshTab,
      context,
      const AutomationAuthoringRequest(originWorkspaceId: 'ws-1'),
    );
    final checkout = chooseAutomationTargetType(
      freshTab,
      AutomationTargetType.projectCheckout,
      context,
      null,
    );
    expect(checkout.field(.workspaceId), isNull);
    expect(checkout.field(.projectId), isNull);
    expect(checkout.whereError, isNotNull);
  });

  test('without context nothing but an only profile is filled', () {
    final draft = chooseAutomationTargetType(
      const AutomationDraft(),
      AutomationTargetType.managedWorkspace,
      automationTestContext(),
      null,
    );
    expect(draft.field(.workspaceId), isNull);
    expect(draft.field(.sourceBranch), isNull);
  });
}
