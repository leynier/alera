import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_segmented_choice.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_host_picker.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// Where a delegated task runs, chosen explicitly: an existing chat in any
/// project or host, a new chat in an existing workspace, or a new workspace
/// with its project, host, mode and setup named.
class const DelegateChatTaskTargetFields({
  super.key,
  required final AgentChatDelegateDraft draft,
  required final ValueChanged<AgentChatDelegateDraftEdit> onEdit,
  required final List<Project> projects,
  required final List<Workspace> Function(String? projectId) workspacesOf,
  required final List<RemoteHostView> hosts,
  required final List<AgentChatDirectoryEntry>? chats,
  final Object? chatsError,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: <Widget>[
      AleraSegmentedChoice<AgentChatTaskTargetKind>(
        label: 'Run In',
        enabled: enabled,
        selected: draft.targetKind,
        onChanged: (kind) =>
            onEdit((draft) => draft.copyWith(targetKind: kind)),
        options: const <AleraSegmentedChoiceOption<AgentChatTaskTargetKind>>[
          AleraSegmentedChoiceOption<AgentChatTaskTargetKind>(
            value: AgentChatTaskTargetKind.chat,
            label: 'Existing Chat',
            helper: 'Continue a chat in any project or host.',
          ),
          AleraSegmentedChoiceOption<AgentChatTaskTargetKind>(
            value: AgentChatTaskTargetKind.workspace,
            label: 'New Chat',
            helper: 'Start a chat in a workspace that already exists.',
          ),
          AleraSegmentedChoiceOption<AgentChatTaskTargetKind>(
            value: AgentChatTaskTargetKind.newWorkspace,
            label: 'New Workspace',
            helper: 'Create a workspace first, then start a chat in it.',
          ),
        ],
      ),
      const SizedBox(height: AleraTokens.space12),
      ...switch (draft.targetKind) {
        AgentChatTaskTargetKind.chat => _chatFields(context),
        AgentChatTaskTargetKind.workspace => _workspaceFields(),
        AgentChatTaskTargetKind.newWorkspace => _newWorkspaceFields(),
      },
    ],
  );

  List<Widget> _chatFields(BuildContext context) {
    final rows = chats == null
        ? null
        : (List<AgentChatDirectoryEntry>.of(chats!)..sort(
            (a, b) => (a.projectName ?? '').compareTo(b.projectName ?? ''),
          ));
    if (rows == null) {
      return <Widget>[
        Text(
          chatsError == null
              ? 'Loading chats…'
              : agentChatOrchestrationErrorMessage(chatsError!),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }
    return <Widget>[
      AleraDropdownField<String>(
        key: const ValueKey<String>('delegateChat'),
        value: draft.chatId,
        labelText: 'Chat',
        hintText: rows.isEmpty ? 'No Chats Yet' : 'Choose a Chat',
        enabled: enabled && rows.isNotEmpty,
        filterable: rows.length > 6,
        filterHintText: 'Search Chats',
        entries: <AleraDropdownFieldEntry<String>>[
          for (final chat in rows)
            AleraDropdownFieldEntry<String>(
              value: chat.chatId,
              label: chat.title,
              detail: _chatPlace(chat),
              group: chat.projectName,
            ),
        ],
        onChanged: (id) => onEdit((draft) => draft.copyWith(chatId: id)),
      ),
    ];
  }

  String _chatPlace(AgentChatDirectoryEntry chat) {
    final project =
        chat.projectName ??
        projects.where((item) => item.id == chat.projectId).firstOrNull?.name;
    final workspace =
        chat.workspaceName ??
        workspacesOf(null)
            .where((item) => item.id == chat.workspaceId)
            .firstOrNull
            ?.name;
    return <String>[?project, ?workspace].join(' / ');
  }

  List<Widget> _workspaceFields() {
    final workspaces = workspacesOf(draft.projectId);
    return <Widget>[
      _projectField(allowAll: true),
      const SizedBox(height: AleraTokens.space8),
      AleraDropdownField<String>(
        key: const ValueKey<String>('delegateWorkspace'),
        value: workspaces.any((item) => item.id == draft.workspaceId)
            ? draft.workspaceId
            : null,
        labelText: 'Workspace',
        hintText: 'Choose a Workspace',
        enabled: enabled && workspaces.isNotEmpty,
        filterable: workspaces.length > 8,
        filterHintText: 'Search Workspaces',
        entries: <AleraDropdownFieldEntry<String>>[
          for (final workspace in workspaces)
            AleraDropdownFieldEntry<String>(
              value: workspace.id,
              label: workspace.name,
              detail: workspace.branch,
              group: projects
                  .where((item) => item.id == workspace.projectId)
                  .firstOrNull
                  ?.name,
            ),
        ],
        onChanged: (id) => onEdit(
          (draft) => draft.copyWith(
            workspaceId: id,
            // The catalog follows the workspace's host, so the agent is
            // chosen again from it.
            providerInstanceId: null,
            model: null,
            runtimeMode: null,
          ),
        ),
      ),
    ];
  }

  Widget _projectField({required bool allowAll}) => AleraDropdownField<String?>(
    key: const ValueKey<String>('delegateProject'),
    value: draft.projectId,
    labelText: 'Project',
    hintText: 'Choose a Project',
    enabled: enabled,
    filterable: projects.length > 8,
    filterHintText: 'Search Projects',
    entries: <AleraDropdownFieldEntry<String?>>[
      if (allowAll)
        const AleraDropdownFieldEntry<String?>(
          value: null,
          label: 'All Projects',
        ),
      for (final project in projects)
        AleraDropdownFieldEntry<String?>(
          value: project.id,
          label: project.name,
        ),
    ],
    onChanged: (id) {
      final project = projects.where((item) => item.id == id).firstOrNull;
      onEdit(
        (draft) => draft.copyWith(
          projectId: id,
          workspaceId: null,
          parentWorkspaceId: null,
          hostId: project == null || project.isOnHost(null)
              ? agentChatLocalHostId
              : project.primaryHostId,
          mode: project != null && !project.supportsLinkedWorkspaces
              ? AgentChatWorkspaceMode.shared
              : draft.mode,
        ),
      );
    },
  );

  List<Widget> _newWorkspaceFields() {
    final project = projects
        .where((item) => item.id == draft.projectId)
        .firstOrNull;
    final worktree = draft.mode == AgentChatWorkspaceMode.worktree;
    return <Widget>[
      _projectField(allowAll: false),
      if (project != null) ...<Widget>[
        const SizedBox(height: AleraTokens.space8),
        WorkspaceHostPicker(
          hostId: draft.hostId == agentChatLocalHostId ? null : draft.hostId,
          hosts: <RemoteHostView>[
            for (final host in hosts)
              if (project.isOnHost(host.id)) host,
          ],
          remoteOnlyProject: !project.isOnHost(null),
          enabled: enabled,
          onChanged: (hostId) => onEdit(
            (draft) => draft.copyWith(hostId: hostId ?? agentChatLocalHostId),
          ),
        ),
        const SizedBox(height: AleraTokens.space12),
        AleraSegmentedChoice<AgentChatWorkspaceMode>(
          label: 'Workspace Type',
          enabled: enabled,
          selected: draft.mode,
          onChanged: (mode) => onEdit((draft) => draft.copyWith(mode: mode)),
          options: <AleraSegmentedChoiceOption<AgentChatWorkspaceMode>>[
            AleraSegmentedChoiceOption<AgentChatWorkspaceMode>(
              value: AgentChatWorkspaceMode.worktree,
              label: agentChatWorkspaceModeLabel(
                AgentChatWorkspaceMode.worktree,
              ),
              helper: 'An isolated Git worktree on its own branch.',
              enabled: project.supportsLinkedWorkspaces,
              disabledReason: 'Folder projects have no Git worktrees.',
            ),
            AleraSegmentedChoiceOption<AgentChatWorkspaceMode>(
              value: AgentChatWorkspaceMode.shared,
              label: agentChatWorkspaceModeLabel(AgentChatWorkspaceMode.shared),
              helper: 'Works in the project folder other workspaces share.',
            ),
          ],
        ),
        if (worktree) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          AleraTextField(
            key: const ValueKey<String>('delegateBranch'),
            labelText: 'Branch',
            hintText: 'Named for the task when empty',
            enabled: enabled,
            onChanged: (value) =>
                onEdit((draft) => draft.copyWith(branch: value)),
          ),
          const SizedBox(height: AleraTokens.space8),
          AleraTextField(
            key: const ValueKey<String>('delegateSourceBranch'),
            labelText: 'Source Branch',
            hintText: "The project's default when empty",
            enabled: enabled,
            onChanged: (value) =>
                onEdit((draft) => draft.copyWith(sourceBranch: value)),
          ),
        ],
        const SizedBox(height: AleraTokens.space8),
        AleraTextField(
          key: const ValueKey<String>('delegateWorkspaceName'),
          labelText: 'Workspace Name',
          hintText: 'Named for the task when empty',
          enabled: enabled,
          onChanged: (value) =>
              onEdit((draft) => draft.copyWith(workspaceName: value)),
        ),
        const SizedBox(height: AleraTokens.space12),
        AleraSegmentedChoice<AgentChatWorkspaceSetup>(
          label: 'Setup',
          enabled: enabled,
          selected: draft.setup,
          onChanged: (setup) => onEdit((draft) => draft.copyWith(setup: setup)),
          options: const <AleraSegmentedChoiceOption<AgentChatWorkspaceSetup>>[
            AleraSegmentedChoiceOption<AgentChatWorkspaceSetup>(
              value: AgentChatWorkspaceSetup.inline,
              label: 'Before Start',
              helper: 'The agent starts once the project setup finished.',
            ),
            AleraSegmentedChoiceOption<AgentChatWorkspaceSetup>(
              value: AgentChatWorkspaceSetup.deferred,
              label: 'In Setup Tab',
              helper: 'Setup runs in a Setup tab while the agent works.',
            ),
          ],
        ),
      ],
    ];
  }
}
