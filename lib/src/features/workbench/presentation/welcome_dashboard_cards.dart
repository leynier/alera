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
  final String? disabledReason,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final row = HoverContainer(
      borderRadius: 0, // Handled by DashboardCard clip.
      onTap: enabled ? onTap : null,
      padding: const .all(AleraTokens.space16),
      child: Opacity(
        opacity: enabled ? 1.0 : AleraTokens.disabledOpacity,
        child: Row(
          children: [
            Icon(icon, size: AleraTokens.iconXxl, color: AleraTokens.accent),
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
              size: AleraTokens.iconLg,
              color: AleraTokens.foregroundFaint,
            ),
          ],
        ),
      ),
    );
    if (enabled || disabledReason == null) {
      return row;
    }
    return Tooltip(message: disabledReason, child: row);
  }
}

class const _ShortcutsCard() extends ConsumerWidget {
  static const List<(KeyboardActionId, String)> _shortcutActions =
      <(KeyboardActionId, String)>[
        (KeyboardActionId.addProject, 'Add Project'),
        (KeyboardActionId.createWorkspace, 'New Workspace'),
        (KeyboardActionId.toggleSidebar, 'Toggle Sidebar'),
        (KeyboardActionId.newTerminalTab, 'New Terminal Tab'),
        (KeyboardActionId.openSettings, 'Open Settings'),
        (KeyboardActionId.splitRight, 'Split Right'),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyboard = ref.watch(settingsControllerProvider).keyboard;
    final resolver = KeybindingResolver(settings: keyboard);

    final isMacOS = resolver.platform.isMacOS;
    final shortcuts = <(String, String)>[
      for (final (id, label) in _shortcutActions)
        if (resolver.effectiveChords(id) case [final chord, ...])
          (label, chord.format(isMacOS: isMacOS)),
    ];
    if (shortcuts.isEmpty) {
      return const SizedBox.shrink();
    }

    return _DashboardCard(
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space16),
        child: Column(
          children: [
            for (var i = 0; i < shortcuts.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AleraTokens.space8),
                  child: Divider(
                    height: AleraTokens.dividerExtent,
                    color: AleraTokens.borderSubtle,
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shortcuts[i].$1,
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
                        child: AleraKeybindingBadge(label: shortcuts[i].$2),
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
