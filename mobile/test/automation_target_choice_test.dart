import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_draft.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the workspace section survives switching between creating targets', () {
    const names = MobileAutomationContext();
    final placed = chooseMobileAutomationTargetType(
      const AutomationDraft(promptTemplate: 'Fix'),
      AutomationTargetType.projectWorktree,
      names,
    ).withTargetField(.workspaceSectionId, 'section-1');
    final switched = chooseMobileAutomationTargetType(
      placed,
      AutomationTargetType.managedWorkspace,
      names,
    );
    expect(switched.workspaceSectionId, 'section-1');
    expect(
      switched.fromContext,
      isNot(contains(AutomationDraftField.workspaceSectionId)),
    );
    final freshTab = chooseMobileAutomationTargetType(
      placed,
      AutomationTargetType.freshTab,
      names,
    );
    expect(freshTab.workspaceSectionId, isNull);
  });

  test(
    'worktree targets parse by parent workspace and serialize as worktree',
    () {
      AutomationRecord record(Map<String, Object?> details) =>
          AutomationRecord.fromJson(<String, Object?>{
            'target': <String, Object?>{'worktree': details},
          });
      final fromWorkspace = record(<String, Object?>{
        'parentWorkspaceId': 'w1',
        'sourceBranch': 'main',
        'agentProfileId': 'codex',
      });
      expect(fromWorkspace.targetType, AutomationTargetType.managedWorkspace);
      expect(fromWorkspace.targetWorkspaceId, 'w1');
      expect(
        AutomationDraft.fromRecord(fromWorkspace).targetJson?['worktree'],
        <String, Object?>{
          'parentWorkspaceId': 'w1',
          'sourceBranch': 'main',
          'nameTemplate': 'auto-{{automation.slug}}-{{run.number}}',
          'agentProfileId': 'codex',
        },
      );
      final fromProject = record(<String, Object?>{'projectId': 'p1'});
      expect(fromProject.targetType, AutomationTargetType.projectWorktree);
      expect(fromProject.targetDetails['projectId'], 'p1');
    },
  );
}
