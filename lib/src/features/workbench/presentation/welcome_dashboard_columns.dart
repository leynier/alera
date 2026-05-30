part of 'welcome_dashboard.dart';

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
              child: Image.asset(
                'assets/logo/alera-logo-white.png',
                width: 32,
                height: 32,
                filterQuality: FilterQuality.medium,
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
