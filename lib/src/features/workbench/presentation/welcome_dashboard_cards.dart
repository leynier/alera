part of 'welcome_dashboard.dart';

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
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AleraTokens.foregroundMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            const Icon(
              AleraIcons.chevronRight,
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
      (KeyboardActionId.addProject, 'Add Project'),
      (KeyboardActionId.createWorkspace, 'New Workspace'),
      (KeyboardActionId.toggleSidebar, 'Toggle Sidebar'),
      (KeyboardActionId.newTerminalTab, 'New Terminal Tab'),
      (KeyboardActionId.openSettings, 'Open Settings'),
      (KeyboardActionId.splitRight, 'Split Right'),
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
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: AleraTokens.foregroundMuted),
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
