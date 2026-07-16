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
        _SectionTitle(title: 'Quick Start'),
        const SizedBox(height: AleraTokens.space12),
        _DashboardCard(
          child: Column(
            children: [
              _ActionRow(
                icon: AleraIcons.newFolder,
                title: 'Add Project',
                description: 'Open a local folder or clone a repository',
                onTap: () => unawaited(showAddProjectFlow(context, ref)),
              ),
              const Divider(height: 1, color: AleraTokens.borderSubtle),
              _ActionRow(
                icon: AleraIcons.gitFork,
                title: 'New Workspace',
                description: 'Create a linked workspace for active Git project',
                enabled: hasGitProjects,
                onTap: () => unawaited(showCreateWorkspaceFlow(context, ref)),
              ),
              const Divider(height: 1, color: AleraTokens.borderSubtle),
              _ActionRow(
                icon: AleraIcons.settings,
                title: 'Open Settings',
                description: 'Configure keyboard shortcuts and preferences',
                onTap: () => unawaited(openSettingsDialog(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RightColumn extends StatelessWidget {
  const _RightColumn();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title: 'Keyboard Shortcuts'),
        SizedBox(height: AleraTokens.space12),
        _ShortcutsCard(),
      ],
    );
  }
}
