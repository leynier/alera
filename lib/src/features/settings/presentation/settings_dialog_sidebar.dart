import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:flutter/material.dart';

const double _kSidebarWidth = 260;
const double _kSidebarIconSize = 16;

class const SettingsSidebar({
  super.key,
  required final TextEditingController queryController,
  required final List<SettingsSectionData> visibleSections,
  required final String? activeSectionId,
  required final ValueChanged<String> onSelect,
  final String query = '',
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _kSidebarWidth,
      child: ColoredBox(
        color: AleraTokens.surfaceVariant,
        child: Column(
          crossAxisAlignment: .stretch,
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
                      fontWeight: .w600,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(
              height: AleraTokens.dividerExtent,
              color: AleraTokens.borderSubtle,
            ),
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space12),
              child: AleraSearchField(
                controller: queryController,
                hintText: 'Search settings',
              ),
            ),
            const Divider(
              height: AleraTokens.dividerExtent,
              color: AleraTokens.borderSubtle,
            ),
            Expanded(
              child: visibleSections.isEmpty
                  ? const AleraEmptyState(message: 'No matching settings.')
                  : ListView(
                      padding: const EdgeInsets.all(AleraTokens.space8),
                      children: _buildNavChildren(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildNavChildren() {
    final children = <Widget>[];
    for (final group in SettingsNavGroup.values) {
      final sections = visibleSections
          .where((section) => section.navGroup == group)
          .toList();
      if (sections.isEmpty) {
        continue;
      }
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AleraTokens.space8));
      }
      children.add(
        AleraSectionHeader(
          label: group.label,
          padding: const EdgeInsets.only(
            left: AleraTokens.space8,
            right: AleraTokens.space8,
            top: AleraTokens.space4,
            bottom: AleraTokens.space4,
          ),
        ),
      );
      for (final section in sections) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space2),
            child: SettingsNavItem(
              section: section,
              active: section.id == activeSectionId,
              matchCount: section.matchCount(query),
              onTap: () => onSelect(section.id),
            ),
          ),
        );
      }
    }
    return children;
  }
}

class const SettingsNavItem({
  super.key,
  required final SettingsSectionData section,
  required final bool active,
  required final VoidCallback onTap,
  this.matchCount = 0,
}) extends StatelessWidget {
  /// Number of matching search entries; shown as a badge while searching.
  final int matchCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: ValueKey<String>('settings-nav-${section.id}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          onTap();
        },
        borderRadius: .circular(AleraTokens.radiusMd),
        mouseCursor: SystemMouseCursors.click,
        child: AleraActiveRail(
          active: active,
          child: Container(
            decoration: BoxDecoration(
              color: active
                  ? AleraActiveRail.selectedColor
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space12,
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
                      color: active
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                      fontWeight: active ? .w600 : .w500,
                    ),
                  ),
                ),
                if (matchCount > 0) AleraBadge(label: '$matchCount'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
