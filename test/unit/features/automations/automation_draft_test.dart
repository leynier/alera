import 'package:alera_automations/alera_automations.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('editable numbers use the runtime bounds and are never clamped', () {
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
        .precheckTimeoutSeconds,
        .inactivityTimeoutSeconds,
        .retryMaxAttempts,
      ]),
    );
    expect(
      errors.containsKey(AutomationNumericField.circuitFailureThreshold),
      isFalse,
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

  test('each step explains what it still needs', () {
    expect(const AutomationDraft().whatError, isNotNull);
    expect(const AutomationDraft(promptTemplate: 'Review').whatError, isNull);
    expect(const AutomationDraft().whenError, isNull);
    expect(
      const AutomationDraft(
        schedule: AutomationSchedulePreset(kind: .weekly, weekdays: {}),
      ).whenError,
      'Choose at least one day.',
    );
  });
}
