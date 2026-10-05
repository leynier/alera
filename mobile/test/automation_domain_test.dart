import 'dart:io';

import 'package:alera_mobile/src/features/automations/domain/automation_draft.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_field_bounds.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _mirrored = <String>[
  'automation_json_fields',
  'automation_readiness',
  'automation_run_models',
  'automation_models',
  'automation_catalog_query',
  'automation_status_labels',
  'automation_schedule_preset',
  'automation_field_bounds',
  'automation_timezones',
  'automation_draft',
  'automation_prompt_variables',
];

void main() {
  test('the mobile automation domain stays a copy of the desktop one', () {
    for (final name in _mirrored) {
      final desktop = File('../lib/src/features/automations/domain/$name.dart')
          .readAsStringSync()
          .replaceAll('package:alera/', 'package:alera_mobile/');
      final mobile = File('lib/src/features/automations/domain/$name.dart')
          .readAsStringSync();
      expect(
        mobile.endsWith(desktop),
        isTrue,
        reason: '$name.dart differs from the desktop copy',
      );
    }
  });

  test('new automations have no target type until the user picks one', () {
    const draft = AutomationDraft(promptTemplate: 'Review');
    expect(draft.targetType, isNull);
    expect(draft.whereError, isNotNull);
  });

  test('create is active unless explicitly a draft', () {
    final draft = const AutomationDraft(promptTemplate: 'Review')
        .withTargetType(AutomationTargetType.freshTab)
        .withTargetField(.workspaceId, 'ws-1')
        .withTargetField(.agentProfileId, 'codex');
    expect(draft.toDefinition().containsKey('state'), isFalse);
    expect(draft.toDefinition(draft: true)['state'], 'draft');
    expect(draft.toDefinition()['misfirePolicy'], 'skip');
  });

  test('numbers follow the runtime bounds without clamping', () {
    final draft = const AutomationDraft().copyWith(
      numbers: <AutomationNumericField, String>{
        .circuitFailureThreshold: '100',
        .circuitOpenSeconds: '604800',
      },
    );
    expect(draft.numberErrors.keys, <AutomationNumericField>[
      AutomationNumericField.circuitFailureThreshold,
    ]);
  });
}
