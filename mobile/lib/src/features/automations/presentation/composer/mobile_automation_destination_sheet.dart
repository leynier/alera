import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_controller.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_destinations.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_destination_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One row of the destination sheet: a target choice and the workspace or
/// project it names, plus the tab for a conversation.
class const MobileAutomationDestinationOption({
  required final AutomationTargetChoice choice,
  required final String id,
  required final String title,
  required final String subtitle,
  required final IconData icon,
  final String? tabId,
  final String? conversationId,
}) {
  bool selectedIn(AutomationDraft draft) {
    final current = AutomationTargetChoice.of(draft);
    if (current != choice) return false;
    final selectedId = switch (choice) {
      AutomationTargetChoice.freshTab ||
      AutomationTargetChoice.existingTab => draft.field(.workspaceId),
      AutomationTargetChoice.workspaceWorktree => draft.field(
        .parentWorkspaceId,
      ),
      AutomationTargetChoice.projectWorktree ||
      AutomationTargetChoice.projectCheckout => draft.field(.projectId),
    };
    return selectedId == id &&
        (choice != AutomationTargetChoice.existingTab ||
            draft.field(.tabId) == tabId);
  }

  AutomationDraft applyTo(
    AutomationDraft draft,
    MobileAutomationContext names,
  ) {
    final fields = <AutomationDraftField, String>{};
    switch (choice) {
      case AutomationTargetChoice.freshTab:
        fields[.workspaceId] = id;
      case AutomationTargetChoice.existingTab:
        fields[.workspaceId] = id;
        if (tabId case final tab?) fields[.tabId] = tab;
        if (conversationId case final conversation?) {
          fields[.conversationId] = conversation;
        }
      case AutomationTargetChoice.workspaceWorktree:
        fields[.parentWorkspaceId] = id;
        final branch = names.workspace(id)?.branch?.trim() ?? '';
        if (branch.isNotEmpty) fields[.sourceBranch] = branch;
      case AutomationTargetChoice.projectWorktree ||
          AutomationTargetChoice.projectCheckout:
        fields[.projectId] = id;
    }
    return applyAutomationDestination(draft, choice, fields);
  }
}

/// The sections of the destination sheet: running agents first, then new
/// tabs, new worktrees and project folders.
List<(String, String?, List<MobileAutomationDestinationOption>)>
mobileAutomationDestinationSections(
  MobileAutomationContext names,
  List<MobileAutomationConversation>? conversations,
) {
  String where(String? projectId, String workspace) =>
      '${names.projectName(projectId)} / $workspace';
  final git = names.projects
      .where((project) => names.isGitProject(project.id))
      .toList(growable: false);
  return <(String, String?, List<MobileAutomationDestinationOption>)>[
    (
      'Running Agents',
      conversations == null ? 'Loading agent conversations...' : 'No open agent conversation can be continued. Start an agent in a tab first.',
      <MobileAutomationDestinationOption>[
        for (final (:workspace, :tab)
            in conversations ?? const <MobileAutomationConversation>[])
          MobileAutomationDestinationOption(
            choice: .existingTab,
            id: workspace.id,
            tabId: tab.id,
            conversationId: tab.agentNativeSessionId,
            title: tab.displayTitle,
            subtitle: where(workspace.projectId, workspace.name),
            icon: AleraIcons.agent,
          ),
      ],
    ),
    (
      'New Tab In A Workspace',
      'No workspaces yet.',
      <MobileAutomationDestinationOption>[
        for (final workspace in names.workspaces)
          MobileAutomationDestinationOption(
            choice: .freshTab,
            id: workspace.id,
            title: workspace.name,
            subtitle: names.projectName(workspace.projectId),
            icon: AleraIcons.tab,
          ),
      ],
    ),
    (
      'New Worktree',
      'Worktrees need a Git project on the paired computer.',
      <MobileAutomationDestinationOption>[
        for (final project in git)
          MobileAutomationDestinationOption(
            choice: .projectWorktree,
            id: project.id,
            title: project.name,
            subtitle: 'From a branch of the project',
            icon: AleraIcons.gitBranch,
          ),
        for (final workspace in names.workspaces)
          if (names.isGitProject(workspace.projectId))
            MobileAutomationDestinationOption(
              choice: .workspaceWorktree,
              id: workspace.id,
              title: workspace.name,
              subtitle:
                  'Child of this workspace in ${names.projectName(workspace.projectId)}',
              icon: AleraIcons.workspaceChildren,
            ),
      ],
    ),
    (
      'Project Folder',
      'No projects yet.',
      <MobileAutomationDestinationOption>[
        for (final project in names.projects)
          MobileAutomationDestinationOption(
            choice: .projectCheckout,
            id: project.id,
            title: project.name,
            subtitle: 'Runs in the project folder, here or on an SSH host',
            icon: AleraIcons.folder,
          ),
      ],
    ),
  ];
}

/// Where the automation runs, chosen from every workspace, project and
/// running conversation. A choice that needs more (a branch, a folder, a
/// conversation) shows those fields at the top and keeps the sheet open.
class MobileAutomationDestinationEditor extends ConsumerStatefulWidget {
  const MobileAutomationDestinationEditor({
    super.key,
    required this.provider,
    required this.hostId,
    required this.close,
  });

  final MobileAutomationComposerControllerProvider provider;
  final String hostId;
  final VoidCallback close;

  @override
  ConsumerState<MobileAutomationDestinationEditor> createState() =>
      _MobileAutomationDestinationEditorState();
}

class _MobileAutomationDestinationEditorState
    extends ConsumerState<MobileAutomationDestinationEditor> {
  String _query = '';

  bool _matches(MobileAutomationDestinationOption option) {
    final query = _query.trim().toLowerCase();
    return query.isEmpty ||
        option.title.toLowerCase().contains(query) ||
        option.subtitle.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(widget.provider.select((state) => state.draft));
    final names =
        ref.watch(mobileAutomationContextProvider(widget.hostId)).value ??
        const MobileAutomationContext();
    final conversations = ref
        .watch(mobileAutomationConversationsProvider(widget.hostId))
        .value;
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final followUp = MobileAutomationDestinationFields.needsFollowUp(draft);
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        if (followUp) ...<Widget>[
          MobileAutomationDestinationFields(
            provider: widget.provider,
            hostId: widget.hostId,
          ),
          const Divider(height: AleraTokens.spaceXl),
        ],
        AleraSearchField(
          hintText: 'Search Workspaces, Projects And Agents',
          onChanged: (value) => setState(() => _query = value),
        ),
        for (final (title, empty, options)
            in mobileAutomationDestinationSections(
              names,
              conversations,
            )) ...<Widget>[
          AleraSectionHeader(label: title),
          if (options.where(_matches).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.spaceXs,
              ),
              child: Text(
                options.isEmpty ? empty ?? '' : 'No matches.',
                style: muted,
              ),
            )
          else
            for (final option in options.where(_matches))
              ListTile(
                contentPadding: EdgeInsets.zero,
                minTileHeight: AleraTokens.minTapTarget,
                leading: Icon(option.icon, size: AleraTokens.iconMd),
                title: Text(option.title, maxLines: 1, overflow: .ellipsis),
                subtitle: Text(
                  option.subtitle,
                  maxLines: 2,
                  overflow: .ellipsis,
                ),
                selected: option.selectedIn(draft),
                trailing: option.selectedIn(draft)
                    ? const Icon(AleraIcons.check, size: AleraTokens.iconMd)
                    : null,
                onTap: () {
                  ref
                      .read(widget.provider.notifier)
                      .update((current) => option.applyTo(current, names));
                  if (!MobileAutomationDestinationFields.needsFollowUp(
                    ref.read(widget.provider).draft,
                  )) {
                    widget.close();
                  }
                },
              ),
        ],
      ],
    );
  }
}
