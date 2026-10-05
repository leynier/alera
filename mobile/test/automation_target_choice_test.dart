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
}
