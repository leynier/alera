import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the workspace section survives switching between creating targets', () {
    const names = MobileAutomationContext();
    final placed = chooseMobileAutomationTargetType(
      const AutomationDraft(promptTemplate: 'Fix'),
      AutomationTargetChoice.projectWorktree,
      names,
    ).withTargetField(.workspaceSectionId, 'section-1');
    final switched = chooseMobileAutomationTargetType(
      placed,
      AutomationTargetChoice.workspaceWorktree,
      names,
    );
    expect(switched.workspaceSectionId, 'section-1');
    expect(
      switched.fromContext,
      isNot(contains(AutomationDraftField.workspaceSectionId)),
    );
    final freshTab = chooseMobileAutomationTargetType(
      placed,
      AutomationTargetChoice.freshTab,
      names,
    );
    expect(freshTab.workspaceSectionId, isNull);
  });
}
