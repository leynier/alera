import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_sectioned_picker.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera/src/features/automations/application/automation_composer_defaults.dart';
import 'package:alera/src/features/automations/application/automation_project_checkouts.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/presentation/automation_popover_chip.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_destination_fields.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One row of the destination picker: a target choice and the workspace or
/// project it names, plus the tab for a conversation.
class const AutomationDestinationOption({
  required final AutomationTargetChoice choice,
  required final String id,
  final String? tabId,
}) {
  /// The row [draft] currently points at, if any.
  static AutomationDestinationOption? of(AutomationDraft draft) {
    final choice = AutomationTargetChoice.of(draft);
    final id = switch (choice) {
      null => null,
      AutomationTargetChoice.freshTab ||
      AutomationTargetChoice.existingTab => draft.field(.workspaceId),
      AutomationTargetChoice.workspaceWorktree => draft.field(
        .parentWorkspaceId,
      ),
      AutomationTargetChoice.projectWorktree ||
      AutomationTargetChoice.projectCheckout => draft.field(.projectId),
    };
    if (choice == null || id == null) return null;
    return AutomationDestinationOption(
      choice: choice,
      id: id,
      tabId: choice == AutomationTargetChoice.existingTab
          ? draft.field(.tabId)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AutomationDestinationOption &&
      other.choice == choice &&
      other.id == id &&
      other.tabId == tabId;

  @override
  int get hashCode => Object.hash(choice, id, tabId);
}

/// Where the automation runs, chosen from every workspace, project and
/// running conversation in a sectioned picker.
class const AutomationDestinationChip({
  required final AutomationComposerControllerProvider provider,
  required final bool hasError,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(provider.select((state) => state.draft));
    final names = ref.watch(automationWorkbenchContextProvider);
    final fromContext = draft.fromContext.any(
      (field) => field != AutomationDraftField.agentProfileId,
    );
    return AutomationPopoverChip(
      icon: AleraIcons.workspaceMain,
      value: draft.targetType == null
          ? 'Choose Destination'
          : automationTargetSummary(
              draft.withTargetField(.agentProfileId, null),
              names,
            ),
      tooltip: 'Destination',
      hasError: hasError,
      fromContext: fromContext,
      width: AleraTokens.dialogWideWidth,
      builder: (context, close) =>
          _DestinationPopover(provider: provider, close: close),
    );
  }
}

class const _DestinationPopover({
  required final AutomationComposerControllerProvider provider,
  required final VoidCallback close,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(provider.select((state) => state.draft));
    final names = ref.watch(automationWorkbenchContextProvider);
    String? folderBlocker(Project project) {
      final folders = ref.watch(automationProjectCheckoutsProvider(project.id));
      return folders.value?.isEmpty == true
          ? 'No registered folder for this project.'
          : null;
    }

    final choice = AutomationTargetChoice.of(draft);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Flexible(
          child: AleraSectionedPicker<AutomationDestinationOption>(
            sections: automationDestinationSections(names, folderBlocker),
            selectedValue: AutomationDestinationOption.of(draft),
            searchHintText: 'Search Workspaces, Projects And Agents',
            onSelected: (option) {
              ref
                  .read(provider.notifier)
                  .update((current) => _apply(current, option, names));
              if (!AutomationDestinationFields.needsFollowUp(option.choice)) {
                close();
              }
            },
          ),
        ),
        if (AutomationDestinationFields.needsFollowUp(choice)) ...<Widget>[
          const Divider(height: AleraTokens.dividerExtent),
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: AutomationDestinationFields(provider: provider),
          ),
        ],
      ],
    );
  }
}

AutomationDraft _apply(
  AutomationDraft draft,
  AutomationDestinationOption option,
  AutomationWorkbenchContext names,
) {
  final fields = <AutomationDraftField, String>{};
  switch (option.choice) {
    case AutomationTargetChoice.freshTab:
      fields[.workspaceId] = option.id;
    case AutomationTargetChoice.existingTab:
      fields[.workspaceId] = option.id;
      final tab = names
          .conversationTabs(option.id)
          .where((item) => item.id == option.tabId)
          .firstOrNull;
      if (tab != null) {
        fields[.tabId] = tab.id;
        if (automationConversationId(tab) case final conversation?) {
          fields[.conversationId] = conversation;
        }
      }
    case AutomationTargetChoice.workspaceWorktree:
      fields[.parentWorkspaceId] = option.id;
      final branch = names.workspace(option.id)?.branch?.trim() ?? '';
      if (branch.isNotEmpty) fields[.sourceBranch] = branch;
    case AutomationTargetChoice.projectWorktree ||
        AutomationTargetChoice.projectCheckout:
      fields[.projectId] = option.id;
  }
  return applyAutomationDestination(draft, option.choice, fields);
}

/// The picker sections: running agents first, then new tabs, new worktrees
/// and project folders. [folderBlocker] explains why a project has no folder
/// to run in, or returns null.
List<AleraPickerSection<AutomationDestinationOption>>
automationDestinationSections(
  AutomationWorkbenchContext names,
  String? Function(Project project) folderBlocker,
) {
  String where(String? projectId, String workspace) =>
      '${names.projectName(projectId)} / $workspace';
  final localGit = names.projects
      .where((project) => project.isGitRepository && !project.isRemoteOnly)
      .toList(growable: false);
  return <AleraPickerSection<AutomationDestinationOption>>[
    AleraPickerSection(
      title: 'Running Agents',
      emptyMessage: 'No open agent conversation can be continued. Start an agent in a tab first.',
      rows: <AleraPickerRow<AutomationDestinationOption>>[
        for (final workspace in names.workspaces)
          for (final tab in names.conversationTabs(workspace.id))
            AleraPickerRow(
              value: AutomationDestinationOption(
                choice: .existingTab,
                id: workspace.id,
                tabId: tab.id,
              ),
              title: tab.title,
              subtitle: where(workspace.projectId, workspace.name),
              leading: const Icon(AleraIcons.agent, size: AleraTokens.iconMd),
            ),
      ],
    ),
    AleraPickerSection(
      title: 'New Tab In A Workspace',
      rows: <AleraPickerRow<AutomationDestinationOption>>[
        for (final workspace in names.workspaces)
          AleraPickerRow(
            value: AutomationDestinationOption(
              choice: .freshTab,
              id: workspace.id,
            ),
            title: workspace.name,
            subtitle: names.projectName(workspace.projectId),
            leading: const Icon(AleraIcons.tab, size: AleraTokens.iconMd),
          ),
      ],
    ),
    AleraPickerSection(
      title: 'New Worktree',
      emptyMessage: 'Worktrees need a Git project on this computer.',
      rows: <AleraPickerRow<AutomationDestinationOption>>[
        for (final project in localGit)
          AleraPickerRow(
            value: AutomationDestinationOption(
              choice: .projectWorktree,
              id: project.id,
            ),
            title: project.name,
            subtitle: 'From a branch of the project',
            leading: const Icon(AleraIcons.gitBranch, size: AleraTokens.iconMd),
          ),
        for (final workspace in names.workspaces)
          if (localGit.any((project) => project.id == workspace.projectId))
            AleraPickerRow(
              value: AutomationDestinationOption(
                choice: .workspaceWorktree,
                id: workspace.id,
              ),
              title: workspace.name,
              subtitle:
                  'Child of this workspace in ${names.projectName(workspace.projectId)}',
              leading: const Icon(
                AleraIcons.workspaceChildren,
                size: AleraTokens.iconMd,
              ),
            ),
      ],
    ),
    AleraPickerSection(
      title: 'Project Folder',
      rows: <AleraPickerRow<AutomationDestinationOption>>[
        for (final project in names.projects)
          AleraPickerRow(
            value: AutomationDestinationOption(
              choice: .projectCheckout,
              id: project.id,
            ),
            title: project.name,
            subtitle: 'Runs in the project folder, here or on an SSH host',
            disabledReason: folderBlocker(project),
            leading: const Icon(AleraIcons.folder, size: AleraTokens.iconMd),
          ),
      ],
    ),
  ];
}
