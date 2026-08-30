part of 'welcome_dashboard.dart';

class const _SectionTitle({required final String title})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: AleraTokens.foregroundMuted, fontWeight: .bold),
    );
  }
}

class const _DashboardCard({required final Widget child})
    extends StatelessWidget {
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

class const _ActionRow({
  required final IconData icon,
  required final String title,
  required final String description,
  required final VoidCallback onTap,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return HoverContainer(
      borderRadius: 0, // Handled by DashboardCard clip.
      onTap: enabled ? onTap : null,
      padding: const .all(AleraTokens.space16),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Row(
          children: [
            Icon(icon, size: 24, color: AleraTokens.accent),
            const SizedBox(width: AleraTokens.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AleraTokens.foreground,
                      fontWeight: .w600,
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

class const _ShortcutsCard() extends ConsumerWidget {
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
                      overflow: .ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: AleraTokens.foregroundMuted),
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: .scaleDown,
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

class const _KeybindingBadge({
  required final KeybindingResolver resolver,
  required final KeyboardActionId actionId,
}) extends StatelessWidget {
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
          fontWeight: .w500,
        ),
      ),
    );
  }
}
