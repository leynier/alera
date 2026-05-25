import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:alera/src/features/keyboard/application/keybinding_resolver.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WelcomeDashboard extends ConsumerWidget {
  const WelcomeDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workbenchControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AleraTokens.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AleraTokens.space32),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 760;
                  final content = [
                    if (isWide) ...[
                      Expanded(flex: 11, child: _LeftColumn(state: state)),
                      const SizedBox(width: AleraTokens.space32),
                      Expanded(flex: 13, child: _RightColumn(state: state)),
                    ] else ...[
                      _LeftColumn(state: state),
                      const SizedBox(height: AleraTokens.space32),
                      _RightColumn(state: state),
                    ],
                  ];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(theme: theme),
                      const SizedBox(height: AleraTokens.space32),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: content,
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: content,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AleraTokens.space8),
              decoration: BoxDecoration(
                color: AleraTokens.surfaceVariant,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                border: Border.all(color: AleraTokens.borderSubtle),
              ),
              child: const Icon(
                Icons.terminal,
                size: 32,
                color: AleraTokens.accent,
              ),
            ),
            const SizedBox(width: AleraTokens.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to Alera',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: AleraTokens.foreground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space4),
                  Text(
                    'A terminal-first agentic developer environment',
                    softWrap: true,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space24),
        const Divider(height: 1, color: AleraTokens.borderSubtle),
      ],
    );
  }
}

class _LeftColumn extends ConsumerWidget {
  const _LeftColumn({required this.state});

  final WorkbenchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasGitProjects = state.projects.any(
      (Project p) => p.supportsLinkedWorkspaces,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title: 'Quick start'),
        const SizedBox(height: AleraTokens.space12),
        _DashboardCard(
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.create_new_folder_outlined,
                title: 'Add project',
                description: 'Open a local folder or clone a repository',
                onTap: () => unawaited(showAddProjectFlow(context, ref)),
              ),
              const Divider(height: 1, color: AleraTokens.borderSubtle),
              _ActionRow(
                icon: Icons.alt_route_outlined,
                title: 'New workspace',
                description: 'Create a linked workspace for active Git project',
                enabled: hasGitProjects,
                onTap: () => unawaited(showCreateWorkspaceFlow(context, ref)),
              ),
              const Divider(height: 1, color: AleraTokens.borderSubtle),
              _ActionRow(
                icon: Icons.settings_outlined,
                title: 'Open settings',
                description: 'Configure keyboard shortcuts and preferences',
                onTap: () => unawaited(openSettingsDialog(context)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space32),
        _SectionTitle(title: 'Keyboard shortcuts'),
        const SizedBox(height: AleraTokens.space12),
        _ShortcutsCard(),
      ],
    );
  }
}

class _RightColumn extends ConsumerWidget {
  const _RightColumn({required this.state});

  final WorkbenchState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = state.projects;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title: 'Projects & workspaces'),
        const SizedBox(height: AleraTokens.space12),
        _DashboardCard(
          child: projects.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AleraTokens.space24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.folder_open,
                        size: 36,
                        color: AleraTokens.foregroundFaint,
                      ),
                      const SizedBox(height: AleraTokens.space16),
                      Text(
                        'No projects registered yet',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: AleraTokens.foregroundMuted),
                      ),
                      const SizedBox(height: AleraTokens.space8),
                      Text(
                        'Add a local folder or clone a repository to get started.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundFaint,
                        ),
                      ),
                      const SizedBox(height: AleraTokens.space16),
                      FilledButton.icon(
                        onPressed: () =>
                            unawaited(showAddProjectFlow(context, ref)),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add project'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: projects.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: AleraTokens.borderSubtle),
                  itemBuilder: (context, index) {
                    final Project project = projects[index];
                    final workspaces = state.workspacesFor(project.id);

                    return Padding(
                      padding: const EdgeInsets.all(AleraTokens.space16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                size: 18,
                                color: AleraTokens.accent,
                              ),
                              const SizedBox(width: AleraTokens.space8),
                              Expanded(
                                child: Text(
                                  project.name,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: AleraTokens.foreground,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AleraTokens.space8),
                          if (workspaces.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: AleraTokens.space24,
                                top: AleraTokens.space4,
                              ),
                              child: Text(
                                'No workspaces for this project',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AleraTokens.foregroundFaint,
                                      fontStyle: FontStyle.italic,
                                    ),
                              ),
                            )
                          else
                            Column(
                              children: [
                                for (final Workspace ws in workspaces)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: AleraTokens.space4,
                                    ),
                                    child: HoverContainer(
                                      borderRadius: AleraTokens.radiusMd,
                                      onTap: () async {
                                        await ref
                                            .read(
                                              workbenchControllerProvider
                                                  .notifier,
                                            )
                                            .selectWorkspace(
                                              project: project,
                                              workspace: ws,
                                            );
                                      },
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AleraTokens.space12,
                                        vertical: AleraTokens.space8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        ws.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                              color: AleraTokens
                                                                  .foreground,
                                                            ),
                                                      ),
                                                    ),
                                                    if (ws.branch
                                                        case final branch?
                                                        when branch
                                                            .trim()
                                                            .isNotEmpty) ...[
                                                      const SizedBox(
                                                        width:
                                                            AleraTokens.space8,
                                                      ),
                                                      Flexible(
                                                        child: Text(
                                                          '($branch)',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .bodySmall
                                                              ?.copyWith(
                                                                color: AleraTokens
                                                                    .foregroundFaint,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(
                                                  height: AleraTokens.space2,
                                                ),
                                                Text(
                                                  ws.path,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: AleraTokens
                                                            .foregroundFaint,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (ws.isMain) ...[
                                            const SizedBox(
                                              width: AleraTokens.space8,
                                            ),
                                            const AleraBadge(label: 'primary'),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: AleraTokens.foregroundMuted,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: child,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return HoverContainer(
      borderRadius: 0, // Handled by DashboardCard clip.
      onTap: enabled ? onTap : null,
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Row(
          children: [
            Icon(icon, size: 24, color: AleraTokens.accent),
            const SizedBox(width: AleraTokens.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AleraTokens.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space2),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: AleraTokens.foregroundFaint,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutsCard extends ConsumerWidget {
  const _ShortcutsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyboard = ref.watch(settingsControllerProvider).keyboard;
    final resolver = KeybindingResolver(settings: keyboard);

    final shortcuts = [
      (KeyboardActionId.addProject, 'Add project'),
      (KeyboardActionId.createWorkspace, 'New workspace'),
      (KeyboardActionId.toggleSidebar, 'Toggle sidebar'),
      (KeyboardActionId.newTerminalTab, 'New terminal tab'),
      (KeyboardActionId.openSettings, 'Open settings'),
      (KeyboardActionId.splitRight, 'Split right'),
    ];

    return _DashboardCard(
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space16),
        child: Column(
          children: [
            for (var i = 0; i < shortcuts.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AleraTokens.space8),
                  child: Divider(height: 1, color: AleraTokens.borderSubtle),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shortcuts[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _KeybindingBadge(
                          resolver: resolver,
                          actionId: shortcuts[i].$1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KeybindingBadge extends StatelessWidget {
  const _KeybindingBadge({required this.resolver, required this.actionId});

  final KeybindingResolver resolver;
  final KeyboardActionId actionId;

  @override
  Widget build(BuildContext context) {
    final chords = resolver.effectiveChords(actionId);
    if (chords.isEmpty) {
      return const SizedBox.shrink();
    }
    final isMacOS = resolver.platform.isMacOS;
    final text = chords.first.format(isMacOS: isMacOS);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Text(
        text,
        style: AleraTokens.monoStyle.copyWith(
          color: AleraTokens.foreground,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
