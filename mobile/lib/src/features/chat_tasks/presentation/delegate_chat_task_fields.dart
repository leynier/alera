import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_mode_labels.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_checkout_selection.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_hosts_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a delegated task runs, chosen explicitly from the projects,
/// workspaces, hosts and chats the paired runtime reports.
class const DelegateChatTaskTargetFields({
  super.key,
  required final String hostId,
  required final AgentChatDelegateDraft draft,
  required final ValueChanged<AgentChatDelegateDraftEdit> onEdit,
  final bool enabled = true,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places =
        ref.watch(mobileChatTaskPlacesProvider(hostId)).value ??
        const MobileChatTaskPlaces();
    final projectId = draft.projectId;
    final project = places.projects
        .where((item) => item.id == projectId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        SegmentedButton<AgentChatTaskTargetKind>(
          key: const ValueKey<String>('delegateTarget'),
          showSelectedIcon: false,
          segments: <ButtonSegment<AgentChatTaskTargetKind>>[
            for (final kind in AgentChatTaskTargetKind.values)
              ButtonSegment<AgentChatTaskTargetKind>(
                value: kind,
                label: Text(kind.label),
                enabled: enabled,
              ),
          ],
          selected: <AgentChatTaskTargetKind>{draft.targetKind},
          onSelectionChanged: (selection) =>
              onEdit((draft) => draft.copyWith(targetKind: selection.single)),
        ),
        const SizedBox(height: AleraTokens.spaceMd),
        if (draft.targetKind == AgentChatTaskTargetKind.chat)
          _ChatField(hostId: hostId, draft: draft, onEdit: onEdit)
        else ...<Widget>[
          AleraDropdownField<String>(
            key: const ValueKey<String>('delegateProject'),
            value: project?.id,
            labelText: 'Project',
            hintText: 'Choose a Project',
            enabled: enabled,
            filterable: places.projects.length > 6,
            entries: <AleraDropdownFieldEntry<String>>[
              for (final item in places.projects)
                AleraDropdownFieldEntry<String>(
                  value: item.id,
                  label: item.name,
                ),
            ],
            onChanged: (id) {
              final next = places.projects.firstWhere((item) => item.id == id);
              onEdit(
                (draft) => draft.copyWith(
                  projectId: id,
                  workspaceId: null,
                  hostId: agentChatLocalHostId,
                  mode: next.supportsLinkedWorkspaces
                      ? draft.mode
                      : AgentChatWorkspaceMode.shared,
                  providerInstanceId: null,
                  model: null,
                ),
              );
            },
          ),
          const SizedBox(height: AleraTokens.spaceSm),
          if (draft.targetKind == AgentChatTaskTargetKind.workspace)
            AleraDropdownField<String>(
              key: const ValueKey<String>('delegateWorkspace'),
              value: draft.workspaceId,
              labelText: 'Workspace',
              hintText: 'Choose a Workspace',
              enabled: enabled && projectId != null,
              filterable: true,
              entries: <AleraDropdownFieldEntry<String>>[
                for (final workspace in places.workspaces)
                  if (workspace.projectId == projectId &&
                      !workspace.isArchived &&
                      workspace.status == 'active')
                    AleraDropdownFieldEntry<String>(
                      value: workspace.id,
                      label: workspace.name,
                    ),
              ],
              onChanged: (id) => onEdit(
                (draft) => draft.copyWith(
                  workspaceId: id,
                  providerInstanceId: null,
                  model: null,
                  runtimeMode: null,
                ),
              ),
            )
          else if (project != null)
            ..._newWorkspaceFields(
              ref,
              supportsWorktree: project.supportsLinkedWorkspaces,
            ),
        ],
      ],
    );
  }

  List<Widget> _newWorkspaceFields(
    WidgetRef ref, {
    required bool supportsWorktree,
  }) {
    final checkouts =
        ref
            .watch(workspaceCheckoutOptionsProvider(hostId, draft.projectId!))
            .value ??
        const [];
    final directory = ref.watch(workspaceHostsControllerProvider(hostId)).value;
    final worktree = draft.mode == AgentChatWorkspaceMode.worktree;
    return <Widget>[
      AleraDropdownField<String>(
        key: const ValueKey<String>('delegateHost'),
        value: checkouts.any((item) => item.hostId == draft.hostId)
            ? draft.hostId
            : null,
        labelText: 'Host',
        hintText: 'Choose Where the Project Lives',
        enabled: enabled,
        entries: <AleraDropdownFieldEntry<String>>[
          for (final checkout in checkouts)
            AleraDropdownFieldEntry<String>(
              value: checkout.hostId,
              label:
                  directory?.byId[checkout.hostId]?.pickerLabel ??
                  checkout.label,
              enabled: directory?.byId[checkout.hostId]?.isReady ?? true,
            ),
        ],
        onChanged: (id) => onEdit((draft) => draft.copyWith(hostId: id)),
      ),
      const SizedBox(height: AleraTokens.spaceSm),
      SegmentedButton<AgentChatWorkspaceMode>(
        key: const ValueKey<String>('delegateMode'),
        showSelectedIcon: false,
        segments: <ButtonSegment<AgentChatWorkspaceMode>>[
          ButtonSegment<AgentChatWorkspaceMode>(
            value: AgentChatWorkspaceMode.worktree,
            label: Text(
              agentChatWorkspaceModeLabel(AgentChatWorkspaceMode.worktree),
            ),
            enabled: enabled && supportsWorktree,
          ),
          ButtonSegment<AgentChatWorkspaceMode>(
            value: AgentChatWorkspaceMode.shared,
            label: Text(
              agentChatWorkspaceModeLabel(AgentChatWorkspaceMode.shared),
            ),
            enabled: enabled,
          ),
        ],
        selected: <AgentChatWorkspaceMode>{draft.mode},
        onSelectionChanged: (selection) =>
            onEdit((draft) => draft.copyWith(mode: selection.single)),
      ),
      if (worktree) ...<Widget>[
        const SizedBox(height: AleraTokens.spaceSm),
        AleraTextField(
          key: const ValueKey<String>('delegateBranch'),
          labelText: 'Branch',
          helperText: 'Named for the task when empty.',
          enabled: enabled,
          onChanged: (value) =>
              onEdit((draft) => draft.copyWith(branch: value)),
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        AleraTextField(
          key: const ValueKey<String>('delegateSourceBranch'),
          labelText: 'Source Branch',
          helperText: "The project's default when empty.",
          enabled: enabled,
          onChanged: (value) =>
              onEdit((draft) => draft.copyWith(sourceBranch: value)),
        ),
      ],
      const SizedBox(height: AleraTokens.spaceSm),
      SegmentedButton<AgentChatWorkspaceSetup>(
        key: const ValueKey<String>('delegateSetup'),
        showSelectedIcon: false,
        segments: <ButtonSegment<AgentChatWorkspaceSetup>>[
          for (final setup in AgentChatWorkspaceSetup.values)
            ButtonSegment<AgentChatWorkspaceSetup>(
              value: setup,
              label: Text(agentChatWorkspaceSetupLabel(setup)),
              enabled: enabled,
            ),
        ],
        selected: <AgentChatWorkspaceSetup>{draft.setup},
        onSelectionChanged: (selection) =>
            onEdit((draft) => draft.copyWith(setup: selection.single)),
      ),
    ];
  }
}

class const _ChatField({
  required final String hostId,
  required final AgentChatDelegateDraft draft,
  required final ValueChanged<AgentChatDelegateDraftEdit> onEdit,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(mobileChatTaskDirectoryProvider(hostId));
    final chats = read.value;
    if (chats == null) {
      return Text(
        read.hasError
            ? agentChatOrchestrationErrorMessage(read.error!)
            : 'Loading chats…',
      );
    }
    return AleraDropdownField<String>(
      key: const ValueKey<String>('delegateChat'),
      value: draft.chatId,
      labelText: 'Chat',
      hintText: chats.isEmpty ? 'No Chats Yet' : 'Choose a Chat',
      enabled: chats.isNotEmpty,
      filterable: true,
      entries: <AleraDropdownFieldEntry<String>>[
        for (final chat in chats)
          AleraDropdownFieldEntry<String>(
            value: chat.chatId,
            label: <String>[chat.title, ?chat.projectName].join(' · '),
          ),
      ],
      onChanged: (id) => onEdit((draft) => draft.copyWith(chatId: id)),
    );
  }
}

/// The agent of a new child chat, from the runtime's catalog only.
class const DelegateChatTaskAgentFields({
  super.key,
  required final AgentChatOrchestrationCapabilities catalog,
  required final AgentChatDelegateDraft draft,
  required final ValueChanged<AgentChatDelegateDraftEdit> onEdit,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider =
        catalog.providers
            .where((item) => item.id == draft.providerInstanceId)
            .firstOrNull ??
        catalog.providers.where((item) => item.available).firstOrNull;
    if (provider == null) {
      return const Text('This host has no agent available for chats.');
    }
    final ceiling = catalog.ceilingRuntimeModes;
    final support = catalog.supportFor(provider.id);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraDropdownField<String>(
          key: const ValueKey<String>('delegateAgent'),
          value: provider.id,
          labelText: 'Agent',
          enabled: enabled,
          entries: <AleraDropdownFieldEntry<String>>[
            for (final item in catalog.providers)
              AleraDropdownFieldEntry<String>(
                value: item.id,
                label: item.available
                    ? item.label
                    : '${item.label} (Unavailable)',
                enabled: item.available,
              ),
          ],
          onChanged: (id) => onEdit(
            (draft) => draft.copyWith(
              providerInstanceId: id,
              model: catalog.providers
                  .firstWhere((item) => item.id == id)
                  .initialModel
                  ?.id,
              runtimeMode: null,
              plan: false,
            ),
          ),
        ),
        if (provider.models.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceSm),
          AleraDropdownField<String>(
            key: const ValueKey<String>('delegateModel'),
            value:
                provider.modelById(draft.model)?.id ??
                provider.initialModel?.id,
            labelText: 'Model',
            enabled: enabled,
            filterable: provider.models.length > 6,
            entries: <AleraDropdownFieldEntry<String>>[
              for (final model in provider.models)
                AleraDropdownFieldEntry<String>(
                  value: model.id,
                  label: model.label,
                ),
            ],
            onChanged: (id) => onEdit(
              (draft) =>
                  draft.copyWith(providerInstanceId: provider.id, model: id),
            ),
          ),
        ],
        if (provider.runtimeModes.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceSm),
          AleraDropdownField<AgentChatRuntimeMode>(
            key: const ValueKey<String>('delegateRuntimeMode'),
            value: draft.runtimeMode,
            labelText: 'Runtime Mode',
            hintText: 'Runtime Default',
            enabled: enabled,
            entries: <AleraDropdownFieldEntry<AgentChatRuntimeMode>>[
              for (final mode in provider.runtimeModes)
                if (ceiling.isEmpty || ceiling.contains(mode))
                  AleraDropdownFieldEntry<AgentChatRuntimeMode>(
                    value: mode,
                    label: agentChatRuntimeModeLabel(mode),
                  ),
            ],
            onChanged: (mode) => onEdit(
              (draft) => draft.copyWith(
                providerInstanceId: provider.id,
                runtimeMode: mode,
              ),
            ),
          ),
        ],
        if (provider.supportsPlanMode)
          SwitchListTile(
            key: const ValueKey<String>('delegatePlan'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Plan First'),
            value: draft.plan,
            onChanged: enabled
                ? (value) => onEdit(
                    (draft) => draft.copyWith(
                      providerInstanceId: provider.id,
                      plan: value,
                    ),
                  )
                : null,
          ),
        if (support != null && !support.supported)
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.spaceSm),
            child: Text(
              support.reason ??
                  'This agent runs the task but cannot delegate further.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.foregroundMuted),
            ),
          ),
      ],
    );
  }
}
