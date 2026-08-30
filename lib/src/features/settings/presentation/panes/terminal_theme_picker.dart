import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';

class const ThemePickerSetting({
  super.key,
  required final String value,
  required final ValueChanged<String> onChanged,
}) extends StatefulWidget {
  @override
  State<ThemePickerSetting> createState() => _ThemePickerSettingState();
}

@visibleForTesting
Widget buildThemePickerSettingForTesting({
  required String value,
  required ValueChanged<String> onChanged,
}) {
  return ThemePickerSetting(value: value, onChanged: onChanged);
}

class _ThemePickerSettingState extends State<ThemePickerSetting> {
  final TextEditingController _controller = TextEditingController();
  int _highlightedIndex = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<TerminalThemeEntry> get _filteredThemes {
    final names = filterOrdered(terminalThemeNames, _controller.text);
    return names
        .map(terminalThemeEntryForName)
        .whereType<TerminalThemeEntry>()
        .toList(growable: false);
  }

  TerminalThemeEntry get _selectedTheme {
    return terminalThemeEntryForName(widget.value) ??
        terminalThemeEntryForName(TerminalThemeNames.aleraDark)!;
  }

  void _selectTheme(TerminalThemeEntry entry) {
    if (entry.name != widget.value) {
      widget.onChanged(entry.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedTheme;
    final filteredThemes = _filteredThemes;
    final searchAndList = _ThemeSearchList(
      controller: _controller,
      selectedName: selected.name,
      themes: filteredThemes,
      highlightedIndex: _highlightedIndex,
      onQueryChanged: (_) => setState(() => _highlightedIndex = -1),
      onHoverTheme: (index) => setState(() => _highlightedIndex = index),
      onSelectTheme: _selectTheme,
    );

    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Text(
            'Theme Preset',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: .w500,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            'Search and select a built-in terminal color theme.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    searchAndList,
                    const SizedBox(height: AleraTokens.space12),
                    _TerminalThemePreview(entry: selected),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: .start,
                children: <Widget>[
                  Expanded(child: searchAndList),
                  const SizedBox(width: AleraTokens.space16),
                  SizedBox(
                    width: 280,
                    child: _TerminalThemePreview(entry: selected),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class const _ThemeSearchList({
  required final TextEditingController controller,
  required final String selectedName,
  required final List<TerminalThemeEntry> themes,
  required final int highlightedIndex,
  required final ValueChanged<String> onQueryChanged,
  required final ValueChanged<int> onHoverTheme,
  required final ValueChanged<TerminalThemeEntry> onSelectTheme,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraSearchField(
          key: const ValueKey<String>('terminal-theme-search-field'),
          controller: controller,
          hintText: 'Search built-in themes',
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: AleraTokens.space8),
        AleraPanel(
          backgroundColor: AleraTokens.surface,
          borderRadius: AleraTokens.radiusMd,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Selected: $selectedName',
                      overflow: .ellipsis,
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Text(
                    'Showing ${themes.length} of ${terminalThemeCatalog.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: kPickerMenuMaxHeight,
              ),
              child: themes.isEmpty
                  ? const AleraEmptyState(message: 'No themes found.')
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        vertical: AleraTokens.space4,
                      ),
                      itemCount: themes.length,
                      itemBuilder: (context, index) {
                        final entry = themes[index];
                        return AleraMenuItem(
                          label: entry.name,
                          active: index == highlightedIndex,
                          selected: entry.name == selectedName,
                          leading: _ThemeColorDots(entry: entry),
                          onHover: () => onHoverTheme(index),
                          onTap: () => onSelectTheme(entry),
                        );
                      },
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

class const _ThemeColorDots({required final TerminalThemeEntry entry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 12,
      child: Row(
        children: <Widget>[
          ThemeColorDot(color: entry.theme.red),
          ThemeColorDot(color: entry.theme.green),
          ThemeColorDot(color: entry.theme.blue),
        ],
      ),
    );
  }
}

class const ThemeColorDot({super.key, required final Color color})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: AleraTokens.space2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
        ),
      ),
    );
  }
}

class const _TerminalThemePreview({required final TerminalThemeEntry entry})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terminalTheme = entry.theme;
    final monoStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'JetBrains Mono',
      color: terminalTheme.foreground,
      height: 1.45,
    );
    return Container(
      decoration: BoxDecoration(
        color: terminalTheme.background,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.border),
      ),
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: DefaultTextStyle.merge(
        style: monoStyle,
        child: Column(
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: terminalTheme.green,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    entry.name,
                    overflow: .ellipsis,
                    maxLines: 1,
                    style: monoStyle?.copyWith(
                      color: terminalTheme.foreground.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            Text(
              r'$ git status --short',
              style: monoStyle?.copyWith(color: terminalTheme.foreground),
            ),
            const SizedBox(height: AleraTokens.space6),
            Text(
              'M  lib/src/features/settings/presentation/settings_dialog.dart',
              maxLines: 1,
              overflow: .ellipsis,
              style: monoStyle?.copyWith(color: terminalTheme.red),
            ),
            Text(
              'A  lib/src/features/settings/domain/terminal_theme_catalog.dart',
              maxLines: 1,
              overflow: .ellipsis,
              style: monoStyle?.copyWith(color: terminalTheme.green),
            ),
            const SizedBox(height: AleraTokens.space8),
            Container(
              color: terminalTheme.selection,
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space2,
              ),
              child: Text(
                'theme preview selected text',
                style: monoStyle?.copyWith(
                  color: terminalTheme.searchHitForeground,
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space8),
            Row(
              mainAxisSize: .min,
              children: <Widget>[
                Text(
                  r'$ echo "cursor" ',
                  style: monoStyle?.copyWith(color: terminalTheme.foreground),
                ),
                Container(width: 7, height: 16, color: terminalTheme.cursor),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
