import 'package:alera/src/features/automations/domain/automation_draft.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AutomationDraft projectWorktree() =>
      const AutomationDraft(promptTemplate: 'Fix')
          .withTargetType(AutomationTargetType.projectWorktree)
          .withTargetField(.projectId, 'project-1')
          .withTargetField(.sourceBranch, 'develop')
          .withTargetField(.agentProfileId, 'codex');

  test('a project worktree needs a project, a branch and a profile', () {
    final empty = const AutomationDraft(promptTemplate: 'Fix')
        .withTargetType(AutomationTargetType.projectWorktree);
    expect(empty.requiredTargetFields, <AutomationDraftField>[
      .projectId,
      .sourceBranch,
      .agentProfileId,
    ]);
    expect(empty.whereError, isNotNull);
    expect(projectWorktree().whereError, isNull);
  });

  test('a project worktree sends its project at both levels', () {
    final definition = projectWorktree().toDefinition();
    expect(definition['projectId'], 'project-1');
    expect(definition['target'], <String, Object?>{
      'projectWorktree': <String, Object?>{
        'projectId': 'project-1',
        'sourceBranch': 'develop',
        'nameTemplate': 'auto-{{automation.slug}}-{{run.number}}',
        'agentProfileId': 'codex',
      },
    });
  });

  test('a saved project worktree reopens with its fields', () {
    final record = AutomationRecord.fromJson(<String, Object?>{
      'id': 'a',
      'slug': 'a',
      'name': 'A',
      'promptTemplate': 'Fix',
      'state': 'active',
      'revision': 1,
      'projectId': 'project-1',
      'schedule': <String, Object?>{
        'recurring': <String, Object?>{'cron': '0 7 * * *', 'timezone': 'UTC'},
      },
      'target': <String, Object?>{
        'projectWorktree': <String, Object?>{
          'projectId': 'project-1',
          'sourceBranch': 'develop',
          'nameTemplate': 'auto-{{automation.slug}}-{{run.number}}',
          'agentProfileId': 'codex',
        },
      },
    });
    expect(record.targetType, AutomationTargetType.projectWorktree);
    final draft = AutomationDraft.fromRecord(record);
    expect(draft.field(.projectId), 'project-1');
    expect(draft.field(.sourceBranch), 'develop');
    expect(draft.field(.agentProfileId), 'codex');
    expect(draft.whereError, isNull);
  });

  test('workspace placement is sent only for targets that create one', () {
    final placed = projectWorktree()
        .withTargetField(.workspaceSectionId, 'section-1')
        .copyWith(workspaceTagIds: <String>['tag-1']);
    expect(placed.toDefinition()['workspacePlacement'], <String, Object?>{
      'tagIds': <String>['tag-1'],
      'sectionId': 'section-1',
    });
    final kept = placed.withTargetType(AutomationTargetType.projectCheckout);
    expect(kept.workspaceSectionId, 'section-1');
    final freshTab = placed.withTargetType(AutomationTargetType.freshTab);
    expect(freshTab.workspaceSectionId, isNull);
    expect(freshTab.toDefinition()['workspacePlacement'], isEmpty);
  });

  test('a saved placement reopens with its tags and section', () {
    final record = AutomationRecord.fromJson(<String, Object?>{
      'id': 'a',
      'slug': 'a',
      'name': 'A',
      'promptTemplate': 'Fix',
      'state': 'active',
      'revision': 1,
      'schedule': <String, Object?>{
        'recurring': <String, Object?>{'cron': '0 7 * * *', 'timezone': 'UTC'},
      },
      'target': <String, Object?>{
        'projectWorktree': <String, Object?>{
          'projectId': 'project-1',
          'sourceBranch': 'main',
          'agentProfileId': 'codex',
        },
      },
      'workspacePlacement': <String, Object?>{
        'tagIds': <String>['tag-1'],
        'sectionId': 'section-1',
      },
    });
    expect(record.workspacePlacement.sectionId, 'section-1');
    final draft = AutomationDraft.fromRecord(record);
    expect(draft.workspaceTagIds, <String>['tag-1']);
    expect(draft.workspaceSectionId, 'section-1');
  });
}
