import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/projects/application/project_hosts_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_host_enrollment.dart';
import 'package:alera/src/features/projects/presentation/project_host_row.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/presentation/add_project_to_host_dialog.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One project as it lives on one host.
class const RemoteHostProjectEntry({
  required final Project project,
  required final String path,
  required final bool primary,
  required final int workspaceCount,
  required final int hostCount,
});

/// The projects on [hostId], from the checkouts the runtime lists and the
/// remote host ids of each project's workspaces, sorted by name.
List<RemoteHostProjectEntry> remoteHostProjectEntries({
  required String hostId,
  required Iterable<Project> projects,
  required Map<String, List<String>> workspaceHostIdsByProject,
}) {
  final entries = <RemoteHostProjectEntry>[];
  for (final project in projects) {
    if (!project.isOnHost(hostId)) {
      continue;
    }
    final primary = project.primaryHostId == hostId;
    final checkout = project.checkouts
        .where((checkout) => checkout.hostId == hostId)
        .firstOrNull;
    final hosts = <String>{
      project.primaryHostId,
      for (final checkout in project.checkouts) checkout.hostId,
    };
    final workspaceHosts =
        workspaceHostIdsByProject[project.id] ?? const <String>[];
    entries.add(
      RemoteHostProjectEntry(
        project: project,
        path: checkout?.path ?? project.repoPath,
        primary: primary,
        workspaceCount: workspaceHosts.where((host) => host == hostId).length,
        hostCount: hosts.length,
      ),
    );
  }
  entries.sort(
    (a, b) =>
        a.project.name.toLowerCase().compareTo(b.project.name.toLowerCase()),
  );
  return entries;
}

/// Projects on This Host: where each lives there, how many workspaces use
/// it, and the controls that add or remove a project on this host.
class const RemoteHostProjectsGroup({
  super.key,
  required final RemoteHostView host,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectListProvider).value ?? const <Project>[];
    final workspacesByProject = ref.watch(
      workbenchControllerProvider.select((state) => state.workspacesByProject),
    );
    final manageable = ref.watch(projectHostsSupportedProvider).value ?? false;
    final entries = remoteHostProjectEntries(
      hostId: host.id,
      projects: projects,
      workspaceHostIdsByProject: <String, List<String>>{
        for (final MapEntry(:key, :value) in workspacesByProject.entries)
          key: <String>[
            for (final workspace in value)
              ?normalizedRemoteHostId(workspace.hostId),
          ],
      },
    );
    final installed =
        host.target.bootstrapStatus == SshBootstrapStatus.installed;
    final canAddExisting = projectsAddableToHost(projects, host.id).isNotEmpty;
    return AleraSettingsGroup(
      title: 'Projects on This Host',
      trailing: manageable && installed
          ? _AddProjectMenu(host: host, canAddExisting: canAddExisting)
          : null,
      children: <Widget>[
        if (entries.isEmpty)
          AleraEmptyState(
            icon: AleraIcons.folderOff,
            title: 'No projects on this host',
            message: installed
                ? 'Add a project to open workspaces on ${host.alias}.'
                : 'Install the Alera runtime before adding projects here.',
            action: manageable && installed
                ? FilledButton(
                    onPressed: () => unawaited(
                      showAddProjectToHostFlow(context, ref, hostId: host.id),
                    ),
                    child: const Text('Add Project to This Host'),
                  )
                : null,
          )
        else
          for (final entry in entries)
            _ProjectRow(
              entry: entry,
              removable: manageable,
              onRemove: () => unawaited(_remove(context, ref, entry)),
            ),
      ],
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    RemoteHostProjectEntry entry,
  ) async {
    final client = ref.read(projectHostsClientProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Remove From Host?',
        message:
            '${entry.project.name} will no longer be on ${host.alias}. Files on the host are not deleted.',
        confirmLabel: 'Remove',
        destructive: true,
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await client.remove(projectId: entry.project.id, hostId: host.id);
      AleraToast.publish(
        message: '${entry.project.name} removed from ${host.alias}',
        tone: .success,
      );
    } catch (error) {
      AleraToast.publish(
        message: userFacingExceptionMessage(error),
        tone: .error,
      );
    }
  }
}

class const _AddProjectMenu({
  required final RemoteHostView host,
  required final bool canAddExisting,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<AddProjectToHostMode>(
      tooltip: 'Add Project to This Host',
      icon: const Icon(AleraIcons.add, size: AleraTokens.iconMd),
      onSelected: (mode) => unawaited(
        showAddProjectToHostFlow(context, ref, hostId: host.id, mode: mode),
      ),
      itemBuilder: (_) => <PopupMenuEntry<AddProjectToHostMode>>[
        AleraDropdownEntry<AddProjectToHostMode>(
          value: .existingProject,
          enabled: canAddExisting,
          leading: const Icon(AleraIcons.gitBranch, size: AleraTokens.iconMd),
          label: 'Add Existing Project…',
        ),
        const AleraDropdownEntry<AddProjectToHostMode>(
          value: .newRemoteProject,
          leading: Icon(AleraIcons.newFolder, size: AleraTokens.iconMd),
          label: 'New Remote Project…',
        ),
      ],
    );
  }
}

class const _ProjectRow({
  required final RemoteHostProjectEntry entry,
  required final bool removable,
  required final VoidCallback onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blockedReason = projectHostRemovalBlockedReason(
      primary: entry.primary,
      workspaceCount: entry.workspaceCount,
      hostCount: entry.hostCount,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            entry.project.isGitRepository
                ? AleraIcons.gitBranch
                : AleraIcons.folder,
            size: AleraTokens.iconLg,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        entry.project.name,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AleraTokens.foreground,
                        ),
                      ),
                    ),
                    if (entry.primary) ...<Widget>[
                      const SizedBox(width: AleraTokens.space8),
                      const AleraBadge(label: 'Primary'),
                    ],
                  ],
                ),
                const SizedBox(height: AleraTokens.space2),
                Text(
                  entry.path,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: AleraTokens.monoCompactStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space12),
          Text(
            projectHostWorkspaceCountLabel(entry.workspaceCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          if (removable) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            AleraIconButton(
              tooltip: blockedReason ?? 'Remove From Host',
              icon: AleraIcons.delete,
              iconColor: blockedReason == null
                  ? AleraTokens.foregroundMuted
                  : AleraTokens.foregroundFaint,
              onPressed: blockedReason == null ? onRemove : null,
            ),
          ],
        ],
      ),
    );
  }
}
