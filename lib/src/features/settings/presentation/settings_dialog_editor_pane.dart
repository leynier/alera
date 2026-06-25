part of 'settings_dialog.dart';

class _EditorSettingsPane extends StatelessWidget {
  const _EditorSettingsPane({required this.settings, required this.onChanged});

  final EditorSettings settings;
  final ValueChanged<EditorSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SettingsGroup(
          title: 'Appearance',
          description: 'Syntax highlighting defaults for editor tabs.',
          children: <Widget>[
            _EditorThemePickerSetting(
              value: settings.themeName,
              onChanged: (value) =>
                  onChanged(settings.copyWith(themeName: value)),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        _SettingsGroup(
          title: 'Indentation',
          description: 'Defaults used by editor tabs.',
          children: <Widget>[
            _IntegerSettingRow(
              title: 'Tab Size',
              description: 'Spaces inserted when pressing Tab.',
              value: settings.tabSize,
              min: 1,
              max: 8,
              step: 1,
              suffix: 'spaces',
              onChanged: (value) =>
                  onChanged(settings.copyWith(tabSize: value)),
            ),
          ],
        ),
      ],
    );
  }
}

class _EditorThemePickerSetting extends StatefulWidget {
  const _EditorThemePickerSetting({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_EditorThemePickerSetting> createState() =>
      _EditorThemePickerSettingState();
}

@visibleForTesting
Widget buildEditorThemePickerSettingForTesting({
  required String value,
  required ValueChanged<String> onChanged,
}) {
  return _EditorThemePickerSetting(value: value, onChanged: onChanged);
}

class _EditorThemePickerSettingState extends State<_EditorThemePickerSetting> {
  final TextEditingController _controller = TextEditingController();
  int _highlightedIndex = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<EditorSyntaxThemeEntry> get _filteredThemes {
    final names = _filterOrdered(editorSyntaxThemeNames, _controller.text);
    return names
        .map(editorSyntaxThemeEntryForName)
        .whereType<EditorSyntaxThemeEntry>()
        .toList(growable: false);
  }

  EditorSyntaxThemeEntry get _selectedTheme {
    return editorSyntaxThemeEntryForName(widget.value) ??
        editorSyntaxThemeCatalog.first;
  }

  void _selectTheme(EditorSyntaxThemeEntry entry) {
    if (entry.name != widget.value) {
      widget.onChanged(entry.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedTheme;
    final filteredThemes = _filteredThemes;
    final searchAndList = _EditorThemeSearchList(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Theme Preset',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            'Search and select a syntax highlighting theme.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    searchAndList,
                    const SizedBox(height: AleraTokens.space12),
                    _EditorThemePreview(entry: selected),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: searchAndList),
                  const SizedBox(width: AleraTokens.space16),
                  SizedBox(
                    width: 280,
                    child: _EditorThemePreview(entry: selected),
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

class _EditorThemeSearchList extends StatelessWidget {
  const _EditorThemeSearchList({
    required this.controller,
    required this.selectedName,
    required this.themes,
    required this.highlightedIndex,
    required this.onQueryChanged,
    required this.onHoverTheme,
    required this.onSelectTheme,
  });

  final TextEditingController controller;
  final String selectedName;
  final List<EditorSyntaxThemeEntry> themes;
  final int highlightedIndex;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<int> onHoverTheme;
  final ValueChanged<EditorSyntaxThemeEntry> onSelectTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AleraSearchField(
          key: const ValueKey<String>('editor-theme-search-field'),
          controller: controller,
          hintText: 'Search syntax themes',
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
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Text(
                    'Showing ${themes.length} of '
                    '${editorSyntaxThemeCatalog.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: _kPickerMenuMaxHeight,
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
                          leading: _EditorThemeColorDots(entry: entry),
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

class _EditorThemeColorDots extends StatelessWidget {
  const _EditorThemeColorDots({required this.entry});

  final EditorSyntaxThemeEntry entry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 12,
      child: Row(
        children: <Widget>[
          _ThemeColorDot(color: _editorThemeColor(entry, 'keyword')),
          _ThemeColorDot(color: _editorThemeColor(entry, 'string')),
          _ThemeColorDot(color: _editorThemeColor(entry, 'title')),
        ],
      ),
    );
  }
}

class _EditorThemePreview extends StatelessWidget {
  const _EditorThemePreview({required this.entry});

  final EditorSyntaxThemeEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = entry.theme['root'];
    final foreground = root?.color ?? AleraTokens.foreground;
    final background = root?.backgroundColor ?? AleraTokens.bg;
    final monoStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'JetBrains Mono',
      color: foreground,
      height: 1.45,
    );

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.border),
      ),
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: DefaultTextStyle.merge(
        style: monoStyle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _editorThemeColor(entry, 'string'),
                    borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    entry.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: monoStyle?.copyWith(
                      color: foreground.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            Text.rich(
              TextSpan(
                style: monoStyle,
                children: <InlineSpan>[
                  TextSpan(
                    text: 'class ',
                    style: _editorThemeStyle(entry, 'keyword'),
                  ),
                  TextSpan(
                    text: 'ThemePreview',
                    style: _editorThemeStyle(entry, 'title.class_'),
                  ),
                  const TextSpan(text: ' {'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text.rich(
              TextSpan(
                style: monoStyle,
                children: <InlineSpan>[
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: 'final ',
                    style: _editorThemeStyle(entry, 'keyword'),
                  ),
                  TextSpan(
                    text: 'name',
                    style: _editorThemeStyle(entry, 'variable'),
                  ),
                  const TextSpan(text: ' = '),
                  TextSpan(
                    text: "'Alera'",
                    style: _editorThemeStyle(entry, 'string'),
                  ),
                  const TextSpan(text: ';'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text.rich(
              TextSpan(
                style: monoStyle,
                children: <InlineSpan>[
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: '// Syntax colors',
                    style: _editorThemeStyle(entry, 'comment'),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Text('}'),
          ],
        ),
      ),
    );
  }
}

TextStyle? _editorThemeStyle(EditorSyntaxThemeEntry entry, String token) {
  return entry.theme[token] ??
      entry.theme[_editorThemeTokenFallback(token)] ??
      entry.theme['root'];
}

String _editorThemeTokenFallback(String token) {
  return switch (token) {
    'title.class_' => 'class-title',
    _ => 'root',
  };
}

Color _editorThemeColor(EditorSyntaxThemeEntry entry, String token) {
  return _editorThemeStyle(entry, token)?.color ??
      entry.theme['root']?.color ??
      AleraTokens.foreground;
}
