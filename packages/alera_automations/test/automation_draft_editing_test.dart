import 'package:alera_automations/alera_automations.dart';
import 'package:test/test.dart';

AutomationDraft _freshTab() =>
    const AutomationDraft(promptTemplate: 'Review')
        .withTargetType(AutomationTargetType.freshTab)
        .withTargetField(.workspaceId, 'ws-1')
        .withTargetField(.agentProfileId, 'codex');

AutomationRecord _stored(JsonMap extra) =>
    AutomationRecord.fromJson(<String, Object?>{
      'id': 'a1',
      'slug': 'nightly',
      'target': <String, Object?>{
        'freshTab': <String, Object?>{
          'workspaceId': 'ws-1',
          'agentProfileId': 'codex',
        },
      },
      ...extra,
    });

void main() {
  test('new automations have no target type until the user picks one', () {
    const draft = AutomationDraft(promptTemplate: 'Review');
    expect(draft.targetType, isNull);
    expect(AutomationTargetChoice.of(draft), isNull);
    expect(draft.whereError, isNotNull);
  });

  test('create is active unless explicitly a draft', () {
    final draft = _freshTab();
    expect(draft.toDefinition().containsKey('state'), isFalse);
    expect(draft.toDefinition(draft: true)['state'], 'draft');
    expect(draft.toDefinition()['misfirePolicy'], 'skip');
  });

  test('only the editable limits are validated and offered', () {
    expect(AutomationNumericField.editableFields, <AutomationNumericField>[
      .inactivityTimeoutSeconds,
      .retryMaxAttempts,
      .precheckTimeoutSeconds,
      .maxScheduledRuns,
    ]);
    final draft = const AutomationDraft().copyWith(
      numbers: <AutomationNumericField, String>{
        .circuitFailureThreshold: '100',
        .retryMaxAttempts: '9',
      },
    );
    expect(draft.numberErrors.keys, <AutomationNumericField>[
      AutomationNumericField.retryMaxAttempts,
    ]);
  });

  test('hidden limits keep their stored values through an edit', () {
    final record = _stored(const <String, Object?>{
      'queueCap': 4,
      'heartbeatIntervalSeconds': 30,
      'misfireGraceSeconds': 120,
      'retryBackoffSeconds': 15,
      'circuitFailureThreshold': 7,
      'circuitOpenSeconds': 3600,
    });
    final definition = AutomationDraft.fromRecord(record).toDefinition();
    expect(definition['queueCap'], 4);
    expect(definition['heartbeatIntervalSeconds'], 30);
    expect(definition['misfireGraceSeconds'], 120);
    expect(definition['retryBackoffSeconds'], 15);
    expect(definition['circuitFailureThreshold'], 7);
    expect(definition['circuitOpenSeconds'], 3600);
  });

  test('the inactivity timeout may not drop below the heartbeat', () {
    final draft = const AutomationDraft().copyWith(
      numbers: <AutomationNumericField, String>{
        .heartbeatIntervalSeconds: '120',
        .inactivityTimeoutSeconds: '60',
      },
    );
    expect(
      draft.numberErrors[AutomationNumericField.inactivityTimeoutSeconds],
      contains('heartbeat'),
    );
  });

  test('worktree choices write one worktree target', () {
    final fromProject = AutomationTargetChoice.projectWorktree
        .applyTo(const AutomationDraft(promptTemplate: 'Run'))
        .withTargetField(.projectId, 'p1')
        .withTargetField(.sourceBranch, 'main')
        .withTargetField(.agentProfileId, 'codex');
    expect(fromProject.whereError, isNull);
    expect(fromProject.toDefinition()['projectId'], 'p1');
    expect(fromProject.targetJson, <String, Object?>{
      'worktree': <String, Object?>{
        'projectId': 'p1',
        'sourceBranch': 'main',
        'nameTemplate': 'auto-{{automation.slug}}-{{run.number}}',
        'agentProfileId': 'codex',
      },
    });
    final fromWorkspace = AutomationTargetChoice.workspaceWorktree.applyTo(
      fromProject,
    );
    expect(fromWorkspace.field(.projectId), isNull);
    expect(
      fromWorkspace.requiredTargetFields.first,
      AutomationDraftField.parentWorkspaceId,
    );
    expect(
      AutomationTargetChoice.of(fromWorkspace),
      AutomationTargetChoice.workspaceWorktree,
    );
  });

  test('the reuse policy is sent only where the runtime understands it', () {
    final reusing = _freshTab().copyWith(
      reusePolicy: AutomationReusePolicy.reuseConversation,
    );
    expect(reusing.toDefinition().containsKey('reusePolicy'), isFalse);
    expect(
      reusing.toDefinition(supportsReuse: true)['reusePolicy'],
      'reuseConversation',
    );
    expect(
      _freshTab().toDefinition(supportsReuse: true).containsKey('reusePolicy'),
      isFalse,
    );
    expect(
      reusing.toDefinition(supportsReuse: true).containsKey('boundTarget'),
      isFalse,
    );
  });

  test('an edit always sends the policy so turning reuse off sticks', () {
    final edit = AutomationDraft.fromRecord(
      _stored(const <String, Object?>{
        'reusePolicy': 'reuseConversation',
        'boundTarget': <String, Object?>{
          'workspaceId': 'ws-1',
          'boundRunId': 'r1',
          'boundAt': '2026-10-01T09:00:00Z',
        },
      }),
    );
    expect(edit.reusePolicy, AutomationReusePolicy.reuseConversation);
    final off = edit.copyWith(reusePolicy: AutomationReusePolicy.newEachRun);
    final definition = off.toDefinition(supportsReuse: true);
    expect(definition['reusePolicy'], 'newEachRun');
    expect(definition.containsKey('boundTarget'), isFalse);
  });

  test('changing the target keeps only a policy that still applies', () {
    final worktree = AutomationTargetChoice.projectWorktree
        .applyTo(const AutomationDraft())
        .copyWith(reusePolicy: AutomationReusePolicy.reuseWorkspace);
    expect(
      worktree.withTargetType(AutomationTargetType.freshTab).reusePolicy,
      AutomationReusePolicy.newEachRun,
    );
    expect(
      worktree.withTargetType(AutomationTargetType.existingTab).reusePolicy,
      AutomationReusePolicy.reuseConversation,
    );
    expect(
      worktree.withTargetType(AutomationTargetType.projectCheckout).reusePolicy,
      AutomationReusePolicy.reuseWorkspace,
    );
  });

  test('the definition key changes with content, not with context marks', () {
    final draft = _freshTab();
    final marked = draft.copyWith(
      fromContext: <AutomationDraftField>{.workspaceId},
    );
    expect(marked.definitionKey, draft.definitionKey);
    expect(
      draft.copyWith(promptTemplate: 'Other').definitionKey,
      isNot(draft.definitionKey),
    );
    expect(
      draft
          .copyWith(reusePolicy: AutomationReusePolicy.reuseConversation)
          .definitionKey,
      isNot(draft.definitionKey),
    );
  });
}
