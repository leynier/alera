import 'package:alera_automations/alera_automations.dart';
import 'package:test/test.dart';

void main() {
  test('a workspace seeds a new tab there, filed in its section', () {
    final draft = seedAutomationDraft(
      const AutomationComposerOrigin(
        originWorkspaceId: 'ws-1',
        workspaceId: 'ws-1',
        worktreeProjectId: 'project-1',
        sectionId: 'section-1',
        profileId: 'codex',
      ),
    );
    expect(draft.targetType, AutomationTargetType.freshTab);
    expect(draft.field(.workspaceId), 'ws-1');
    expect(draft.field(.agentProfileId), 'codex');
    expect(draft.originWorkspaceId, 'ws-1');
    expect(draft.workspaceSectionId, 'section-1');
    expect(draft.fromContext, <AutomationDraftField>{.workspaceId});
  });

  test('a Git project seeds a worktree, its branch once listed', () {
    final draft = seedAutomationDraft(
      const AutomationComposerOrigin(worktreeProjectId: 'project-1'),
    );
    expect(
      AutomationTargetChoice.of(draft),
      AutomationTargetChoice.projectWorktree,
    );
    expect(draft.fromContext, <AutomationDraftField>{.projectId});
    final branched = automationSeedSourceBranch(draft, 'project-1', 'develop');
    expect(branched.field(.sourceBranch), 'develop');
    expect(branched.fromContext, <AutomationDraftField>{
      .projectId,
      .sourceBranch,
    });
    final chosen = branched.withTargetField(.sourceBranch, 'main');
    expect(
      automationSeedSourceBranch(
        chosen,
        'project-1',
        'develop',
      ).field(.sourceBranch),
      'main',
    );
    expect(automationSeedSourceBranch(draft, 'other', 'develop'), same(draft));
  });

  test('a project folder is seeded only when it is the only one', () {
    final draft = seedAutomationDraft(
      const AutomationComposerOrigin(profileId: 'codex'),
    );
    const folder = (hostId: 'local', path: '/notes');
    expect(
      automationSeedProjectFolder(draft, 'folder', const []).targetType,
      isNull,
    );
    expect(
      automationSeedProjectFolder(draft, 'folder', const [
        folder,
        (hostId: 'ssh-1', path: '/srv/notes'),
      ]).targetType,
      isNull,
    );
    final seeded = automationSeedProjectFolder(draft, 'folder', const [folder]);
    expect(seeded.targetType, AutomationTargetType.projectCheckout);
    expect(seeded.field(.hostId), 'local');
    expect(seeded.field(.agentProfileId), 'codex');
    expect(seeded.fromContext, <AutomationDraftField>{.projectId, .hostId});
  });

  test('a section seeds only where new workspaces land', () {
    final draft = seedAutomationDraft(
      const AutomationComposerOrigin(sectionId: 'section-1'),
    );
    expect(draft.targetType, isNull);
    expect(draft.workspaceSectionId, 'section-1');
    expect(draft.fromContext, isEmpty);
    expect(draft.destinationError, 'Choose where the automation runs.');
  });

  test('the agent is the last used, then the default, then the only one', () {
    const profiles = <String>['a', 'b'];
    expect(
      automationPreferredProfileId(
        profiles,
        lastUsed: 'b',
        settingsDefault: 'a',
      ),
      'b',
    );
    expect(
      automationPreferredProfileId(
        profiles,
        lastUsed: 'gone',
        settingsDefault: 'a',
      ),
      'a',
    );
    expect(automationPreferredProfileId(profiles), isNull);
    expect(automationPreferredProfileId(const <String>['a']), 'a');
  });

  test('changing the destination keeps the agent and the section', () {
    final draft = seedAutomationDraft(
      const AutomationComposerOrigin(
        workspaceId: 'ws-1',
        sectionId: 'section-1',
        profileId: 'codex',
      ),
    );
    final worktree = applyAutomationDestination(
      draft,
      AutomationTargetChoice.projectWorktree,
      const <AutomationDraftField, String>{.projectId: 'project-1'},
    );
    expect(worktree.field(.workspaceId), isNull);
    expect(worktree.field(.projectId), 'project-1');
    expect(worktree.field(.agentProfileId), 'codex');
    expect(worktree.workspaceSectionId, 'section-1');
    expect(worktree.fromContext, isEmpty);
  });
}
