import 'package:alera_automations/alera_automations.dart';
import 'package:test/test.dart';

class const _Names() implements AutomationNameLookup {
  @override
  String projectName(String? id) => 'Project $id';

  @override
  String workspaceName(String? id) => 'Workspace $id';

  @override
  String hostName(String? id) => 'Host $id';

  @override
  String profileName(String? id) => 'Profile $id';
}

void main() {
  const names = _Names();

  test('every destination reads as names, never ids alone', () {
    AutomationDraft draft(AutomationTargetChoice choice) =>
        choice.applyTo(const AutomationDraft());
    expect(
      automationTargetSummary(const AutomationDraft(), names),
      'No target',
    );
    expect(
      automationTargetSummary(
        draft(AutomationTargetChoice.freshTab)
            .withTargetField(.workspaceId, 'w1')
            .withTargetField(.agentProfileId, 'codex'),
        names,
      ),
      'New tab in Workspace w1 · Profile codex',
    );
    expect(
      automationTargetSummary(
        draft(AutomationTargetChoice.projectWorktree)
            .withTargetField(.projectId, 'p1'),
        names,
      ),
      'New worktree of Project p1 from its default branch',
    );
    expect(
      automationTargetSummary(
        draft(AutomationTargetChoice.workspaceWorktree)
            .withTargetField(.parentWorkspaceId, 'w2')
            .withTargetField(.sourceBranch, 'main'),
        names,
      ),
      'New worktree from Workspace w2 on main',
    );
    expect(
      automationTargetSummary(
        draft(AutomationTargetChoice.projectCheckout)
            .withTargetField(.projectId, 'p1')
            .withTargetField(.hostId, 'h1'),
        names,
      ),
      'Folder of Project p1 on Host h1',
    );
    expect(
      automationTargetSummary(
        draft(AutomationTargetChoice.existingTab)
            .withTargetField(.workspaceId, 'w3'),
        names,
      ),
      'Conversation in Workspace w3',
    );
  });

  test('a stored definition prefers the runtime summary', () {
    final target = <String, Object?>{
      'freshTab': <String, Object?>{'workspaceId': 'w1'},
    };
    expect(
      automationRecordTargetSummary(
        AutomationRecord.fromJson(<String, Object?>{
          'target': target,
          'targetSummary': 'Main on the build box',
        }),
        names,
      ),
      'Main on the build box',
    );
    expect(
      automationRecordTargetSummary(
        AutomationRecord.fromJson(<String, Object?>{'target': target}),
        names,
      ),
      'New tab in Workspace w1',
    );
  });
}
