part of 'settings_dialog.dart';

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.queryController,
    required this.visibleSections,
    required this.activeSectionId,
    required this.onSelect,
  });

  final TextEditingController queryController;
  final List<_SettingsSectionData> visibleSections;
  final String? activeSectionId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _kSidebarWidth,
      child: ColoredBox(
        color: AleraTokens.surfaceVariant,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: AleraTokens.sidebarHeaderHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Settings',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AleraTokens.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space12),
              child: AleraSearchField(
                controller: queryController,
                hintText: 'Search settings',
              ),
            ),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            Expanded(
              child: visibleSections.isEmpty
                  ? const AleraEmptyState(message: 'No matching settings.')
                  : ListView.separated(
                      padding: const EdgeInsets.all(AleraTokens.space8),
                      itemCount: visibleSections.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AleraTokens.space2),
                      itemBuilder: (_, index) {
                        final section = visibleSections[index];
                        return _SettingsNavItem(
                          section: section,
                          active: section.id == activeSectionId,
                          onTap: () => onSelect(section.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({
    required this.section,
    required this.active,
    required this.onTap,
  });

  final _SettingsSectionData section;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          onTap();
        },
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          decoration: BoxDecoration(
            color: active ? AleraTokens.surfaceElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space8,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                section.icon,
                size: _kSidebarIconSize,
                color: active
                    ? AleraTokens.foreground
                    : AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  section.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AleraTokens.foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({required this.section, required this.onClose});

  final _SettingsSectionData section;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AleraTokens.space24),
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(
                  section.icon,
                  size: _kSectionIconSize,
                  color: AleraTokens.accent,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(section.title, style: theme.textTheme.titleLarge),
                ),
                if (section.onReset != null) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  TextButton(
                    onPressed: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      await Future<void>.delayed(Duration.zero);
                      await section.onReset!();
                    },
                    child: Text('Reset ${section.title.toLowerCase()}'),
                  ),
                ],
                const SizedBox(width: AleraTokens.space4),
                AleraIconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: Icons.close,
                  minSize: 34,
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space4),
            Text(
              section.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space20),
        section.builder(context),
      ],
    );
  }
}
