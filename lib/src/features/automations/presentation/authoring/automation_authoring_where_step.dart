import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/automations/application/automation_authoring_controller.dart';
import 'package:alera/src/features/automations/application/automation_project_checkouts.dart';
import 'package:alera/src/features/automations/application/automation_target_context.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_draft.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/presentation/authoring/automation_project_worktree_fields.dart';
import 'package:alera/src/features/automations/presentation/authoring/automation_workspace_placement_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _targetDescription(AutomationTargetType type) => switch (type) {
  AutomationTargetType.freshTab =>
    'Each run opens a new agent tab in a workspace you choose.',
  AutomationTargetType.projectWorktree => 'Each run creates a new workspace with its own worktree and branch from a project branch, then opens an agent tab there. Git projects on this computer only.',
  AutomationTargetType.managedWorkspace => 'Each run creates a child workspace with its own worktree and branch from a workspace you choose. Git projects on this computer only.',
  AutomationTargetType.projectCheckout => 'Each run creates a workspace on a registered project folder, here or on an SSH host. Files are shared.',
  AutomationTargetType.existingTab =>
    'Each run sends the prompt to an agent conversation that is already open.',
};

/// The execution target is the one choice that is never made for the user:
/// no card starts selected, whatever page or menu opened the flow.
class const AutomationWhereStep({
  required final AutomationAuthoringControllerProvider provider,
  required final AutomationAuthoringRequest request,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final names = ref.watch(automationWorkbenchContextProvider);
    final draft = state.draft;
    final theme = Theme.of(context);
    final conversationsAvailable = names.workspaces.any(
      (workspace) => names.conversationTabs(workspace.id).isNotEmpty,
    );
    final origin = names.workspace(draft.originWorkspaceId);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (origin != null) ...<Widget>[
          Text(
            'Created from ${origin.name}. This shows the automation in that workspace and its section; it does not choose where it runs.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space12),
        ],
        Text('Where Should It Run?', style: theme.textTheme.titleSmall),
        const SizedBox(height: AleraTokens.space8),
        for (final type in AutomationTargetType.values)
          _TargetTypeCard(
            type: type,
            selected: draft.targetType == type,
            disabledReason:
                type == AutomationTargetType.existingTab &&
                    !conversationsAvailable
                ? 'Open an agent tab whose conversation Alera can resume to use this.'
                : null,
            onSelect: () => controller.update(
              (current) =>
                  chooseAutomationTargetType(current, type, names, request),
            ),
          ),
        if (draft.targetType != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          _TargetFields(provider: provider, draft: draft, names: names),
          if (draft.targetType!.createsWorkspace) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            AutomationWorkspacePlacementFields(
              provider: provider,
              draft: draft,
              names: names,
            ),
          ],
        ],
      ],
    );
  }
}

class const _TargetTypeCard({
  required final AutomationTargetType type,
  required final bool selected,
  required final VoidCallback onSelect,
  final String? disabledReason,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final enabled = disabledReason == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space6),
      child: Material(
        color: selected ? AleraTokens.accentSubtle : AleraTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          side: BorderSide(
            color: selected ? AleraTokens.accent : AleraTokens.borderSubtle,
          ),
        ),
        child: ListTile(
          enabled: enabled,
          selected: selected,
          onTap: enabled ? onSelect : null,
          leading: Icon(
            selected ? AleraIcons.radioOn : AleraIcons.radioOff,
            size: AleraTokens.iconMd,
          ),
          title: Text(type.label),
          subtitle: Text(disabledReason ?? _targetDescription(type)),
        ),
      ),
    );
  }
}

class const _TargetFields({
  required final AutomationAuthoringControllerProvider provider,
  required final AutomationDraft draft,
  required final AutomationWorkbenchContext names,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(provider.notifier);
    final type = draft.targetType!;
    void set(AutomationDraftField field, String? value) =>
        controller.update((current) => current.withTargetField(field, value));
    Widget picker({
      required AutomationDraftField field,
      required String label,
      required List<AleraDropdownFieldEntry<String?>> entries,
      ValueChanged<String?>? onChanged,
    }) {
      final value = draft.field(field);
      final known = entries.any((entry) => entry.value == value);
      return AutomationContextMarked(
        fromContext: draft.fromContext.contains(field),
        child: AleraDropdownField<String?>(
          labelText: label,
          value: known ? value : null,
          hintText: 'Choose',
          filterable: entries.length > 8,
          filterHintText: 'Search',
          entries: entries,
          onChanged: onChanged ?? (next) => set(field, next),
        ),
      );
    }

    final workspaceEntries = <AleraDropdownFieldEntry<String?>>[
      for (final workspace in names.workspaces)
        if (type != AutomationTargetType.managedWorkspace ||
            names.project(workspace.projectId)?.isGitRepository == true)
          AleraDropdownFieldEntry(
            value: workspace.id,
            label:
                '${names.projectName(workspace.projectId)} / ${workspace.name}',
          ),
    ];
    final profileEntries = <AleraDropdownFieldEntry<String?>>[
      for (final profile in names.profiles)
        AleraDropdownFieldEntry(value: profile.id, label: profile.name),
    ];
    final children = <Widget>[];
    switch (type) {
      case AutomationTargetType.freshTab:
        children.add(
          picker(
            field: .workspaceId,
            label: 'Workspace',
            entries: workspaceEntries,
          ),
        );
      case AutomationTargetType.managedWorkspace:
        children.add(
          picker(
            field: .workspaceId,
            label: 'Source Workspace',
            entries: workspaceEntries,
            onChanged: (value) => controller.update((current) {
              var next = current.withTargetField(.workspaceId, value);
              final branch = names.workspace(value)?.branch?.trim();
              if (branch != null && branch.isNotEmpty) {
                next = next.withTargetField(.sourceBranch, branch);
                next = next.copyWith(
                  fromContext: <AutomationDraftField>{
                    ...next.fromContext,
                    .sourceBranch,
                  },
                );
              }
              return next;
            }),
          ),
        );
        children.add(
          AutomationContextMarked(
            fromContext: draft.fromContext.contains(
              AutomationDraftField.sourceBranch,
            ),
            child: _BranchField(
              key: ValueKey<String?>(draft.field(.workspaceId)),
              value: draft.field(.sourceBranch) ?? '',
              onChanged: (value) => set(.sourceBranch, value),
            ),
          ),
        );
      case AutomationTargetType.projectWorktree:
        children.add(
          AutomationProjectWorktreeFields(
            provider: provider,
            draft: draft,
            names: names,
          ),
        );
      case AutomationTargetType.projectCheckout:
        final projectId = draft.field(.projectId);
        final checkouts = projectId == null
            ? null
            : ref.watch(automationProjectCheckoutsProvider(projectId));
        children.add(
          picker(
            field: .projectId,
            label: 'Project',
            entries: <AleraDropdownFieldEntry<String?>>[
              for (final project in names.projects)
                AleraDropdownFieldEntry(value: project.id, label: project.name),
            ],
            onChanged: (value) => controller.update(
              (current) => current
                  .withTargetField(.projectId, value)
                  .withTargetField(.hostId, null),
            ),
          ),
        );
        if (projectId != null) {
          children.add(
            picker(
              field: .hostId,
              label: 'Project Folder',
              entries: <AleraDropdownFieldEntry<String?>>[
                for (final checkout
                    in checkouts?.value ??
                        const <({String hostId, String path})>[])
                  AleraDropdownFieldEntry(
                    value: checkout.hostId,
                    label:
                        '${names.hostName(checkout.hostId)}: ${checkout.path}',
                  ),
              ],
            ),
          );
          if (checkouts?.hasError == true) {
            children.add(
              const Text(
                'Could not load project folders. Check the runtime connection and try again.',
              ),
            );
          }
        }
      case AutomationTargetType.existingTab:
        final workspaceId = draft.field(.workspaceId);
        children.add(
          picker(
            field: .workspaceId,
            label: 'Workspace',
            entries: <AleraDropdownFieldEntry<String?>>[
              for (final workspace in names.workspaces)
                if (names.conversationTabs(workspace.id).isNotEmpty)
                  AleraDropdownFieldEntry(
                    value: workspace.id,
                    label:
                        '${names.projectName(workspace.projectId)} / ${workspace.name}',
                  ),
            ],
            onChanged: (value) => controller.update(
              (current) => current
                  .withTargetField(.workspaceId, value)
                  .withTargetField(.tabId, null)
                  .withTargetField(.conversationId, null),
            ),
          ),
        );
        if (workspaceId != null) {
          final tabs = names.conversationTabs(workspaceId);
          children.add(
            picker(
              field: .tabId,
              label: 'Agent Tab',
              entries: <AleraDropdownFieldEntry<String?>>[
                for (final tab in tabs)
                  AleraDropdownFieldEntry(value: tab.id, label: tab.title),
              ],
              onChanged: (value) => controller.update((current) {
                final tab = tabs.where((item) => item.id == value).firstOrNull;
                return current
                    .withTargetField(.tabId, value)
                    .withTargetField(
                      .conversationId,
                      tab == null ? null : automationConversationId(tab),
                    );
              }),
            ),
          );
        }
    }
    if (type != AutomationTargetType.existingTab) {
      children.add(
        picker(
          field: .agentProfileId,
          label: 'Agent Profile',
          entries: profileEntries,
        ),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final child in children) ...<Widget>[
          child,
          const SizedBox(height: AleraTokens.space12),
        ],
        if (draft.fromContext.isNotEmpty)
          Text(
            'Fields marked From Context were filled from where you started. Change any of them freely.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
      ],
    );
  }
}

class _BranchField extends StatefulWidget {
  const _BranchField({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_BranchField> createState() => _BranchFieldState();
}

class _BranchFieldState extends State<_BranchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AleraTextField(
    controller: _controller,
    labelText: 'Source Branch',
    onChanged: widget.onChanged,
  );
}
