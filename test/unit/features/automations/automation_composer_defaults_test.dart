import 'package:alera/src/features/automations/application/automation_composer_defaults.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/automation_test_harness.dart';

AutomationWorkbenchContext _context() {
  final base = automationTestContext();
  final now = DateTime.utc(2026);
  return AutomationWorkbenchContext(
    projects: <Project>[
      ...base.projects,
      Project(
        id: 'folder',
        name: 'Notes',
        repoPath: '/notes',
        kind: ProjectKind.folder,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    workspaces: <Workspace>[
      for (final workspace in base.workspaces)
        workspace.id == 'ws-1'
            ? workspace.copyWith(sectionId: 'section-1')
            : workspace,
    ],
    profiles: base.profiles,
    tabsByWorkspace: base.tabsByWorkspace,
  );
}

void main() {
  test('a workspace seeds a new tab there, filed in its section', () {
    final draft = seedAutomationComposerDraft(
      const AutomationAuthoringRequest(originWorkspaceId: 'ws-1'),
      _context(),
      profileId: 'codex',
    );
    expect(draft.targetType, AutomationTargetType.freshTab);
    expect(draft.field(.workspaceId), 'ws-1');
    expect(draft.field(.agentProfileId), 'codex');
    expect(draft.originWorkspaceId, 'ws-1');
    expect(draft.workspaceSectionId, 'section-1');
    expect(draft.fromContext, <AutomationDraftField>{.workspaceId});
    expect(draft.localProblems.keys, <AutomationComposerProperty>[.prompt]);
  });

  test('a local Git project seeds a worktree, its branch once listed', () {
    final draft = seedAutomationComposerDraft(
      const AutomationAuthoringRequest(projectId: 'project-1'),
      _context(),
    );
    expect(
      AutomationTargetChoice.of(draft),
      AutomationTargetChoice.projectWorktree,
    );
    expect(draft.field(.projectId), 'project-1');
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
  });

  test('another project seeds its folder only when it has exactly one', () {
    final draft = seedAutomationComposerDraft(
      const AutomationAuthoringRequest(projectId: 'folder'),
      _context(),
      profileId: 'codex',
    );
    expect(draft.targetType, isNull);
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
    final draft = seedAutomationComposerDraft(
      const AutomationAuthoringRequest(sectionId: 'section-1'),
      _context(),
    );
    expect(draft.targetType, isNull);
    expect(draft.workspaceSectionId, 'section-1');
    expect(draft.fromContext, isEmpty);
  });

  test('without context there is no destination to save', () {
    final draft = seedAutomationComposerDraft(
      const AutomationAuthoringRequest(),
      _context(),
    );
    expect(draft.targetType, isNull);
    expect(draft.destinationError, 'Choose where the automation runs.');
  });

  test('changing the destination keeps the agent and the section', () {
    final draft = seedAutomationComposerDraft(
      const AutomationAuthoringRequest(originWorkspaceId: 'ws-1'),
      _context(),
      profileId: 'codex',
    );
    final worktree = applyAutomationDestination(
      draft,
      AutomationTargetChoice.projectWorktree,
      const <AutomationDraftField, String>{.projectId: 'project-1'},
    );
    expect(worktree.field(.workspaceId), isNull);
    expect(worktree.field(.agentProfileId), 'codex');
    expect(worktree.workspaceSectionId, 'section-1');
    expect(worktree.fromContext, isEmpty);
  });
}
