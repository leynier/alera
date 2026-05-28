part of 'settings_dialog.dart';

class _TerminalSettingsPane extends StatelessWidget {
  const _TerminalSettingsPane({
    required this.settings,
    required this.fontSuggestions,
    required this.onChanged,
  });

  final TerminalSettings settings;
  final List<String> fontSuggestions;
  final ValueChanged<TerminalSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final overrides = settings.colorOverrides;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SettingsGroup(
          title: 'Typography',
          description: 'Default terminal typography for new sessions.',
          children: <Widget>[
            _FontAutocompleteSettingRow(
              title: 'Font family',
              description: 'Typeface used in new terminal sessions.',
              value: settings.fontFamily,
              suggestions: fontSuggestions,
              onChanged: (value) =>
                  onChanged(settings.copyWith(fontFamily: value)),
            ),
            _NumberSettingRow(
              title: 'Font size',
              description: 'Text size used in new terminal sessions.',
              value: settings.fontSize,
              min: 8,
              max: 32,
              step: 1,
              suffix: 'px',
              onChanged: (value) =>
                  onChanged(settings.copyWith(fontSize: value)),
            ),
            _IntegerSettingRow(
              title: 'Font weight',
              description: 'Weight used for terminal text.',
              value: settings.fontWeight,
              min: 100,
              max: 900,
              step: 100,
              onChanged: (value) =>
                  onChanged(settings.copyWith(fontWeight: value)),
            ),
            _NumberSettingRow(
              title: 'Line height',
              description: 'Vertical spacing for terminal rows.',
              value: settings.lineHeight,
              min: 0.8,
              max: 2.4,
              step: 0.1,
              onChanged: (value) =>
                  onChanged(settings.copyWith(lineHeight: value)),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        _SettingsGroup(
          title: 'Cursor',
          description: 'Default cursor appearance for terminal sessions.',
          children: <Widget>[
            _CursorShapeRow(
              value: settings.cursorShape,
              onChanged: (value) =>
                  onChanged(settings.copyWith(cursorShape: value)),
            ),
            _SwitchSettingRow(
              title: 'Blinking cursor',
              description: 'Blink the cursor while the terminal has focus.',
              value: settings.cursorBlink,
              onChanged: (value) =>
                  onChanged(settings.copyWith(cursorBlink: value)),
            ),
            _NumberSettingRow(
              title: 'Cursor opacity',
              description: 'Opacity of the terminal cursor.',
              value: settings.cursorOpacity,
              min: 0,
              max: 1,
              step: 0.05,
              onChanged: (value) =>
                  onChanged(settings.copyWith(cursorOpacity: value)),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        _SettingsGroup(
          title: 'Appearance',
          description: 'Terminal colors, theme and spacing.',
          children: <Widget>[
            _ThemePickerSetting(
              value: settings.themeName,
              onChanged: (value) =>
                  onChanged(settings.copyWith(themeName: value)),
            ),
            _NumberSettingRow(
              title: 'Background opacity',
              description: 'Opacity of the terminal background.',
              value: settings.backgroundOpacity,
              min: 0,
              max: 1,
              step: 0.05,
              onChanged: (value) =>
                  onChanged(settings.copyWith(backgroundOpacity: value)),
            ),
            _NumberSettingRow(
              title: 'Horizontal padding',
              description: 'Horizontal spacing around the terminal grid.',
              value: settings.paddingX,
              min: 0,
              max: 64,
              step: 1,
              suffix: 'px',
              onChanged: (value) =>
                  onChanged(settings.copyWith(paddingX: value)),
            ),
            _NumberSettingRow(
              title: 'Vertical padding',
              description: 'Vertical spacing around the terminal grid.',
              value: settings.paddingY,
              min: 0,
              max: 64,
              step: 1,
              suffix: 'px',
              onChanged: (value) =>
                  onChanged(settings.copyWith(paddingY: value)),
            ),
            _HexColorSettingRow(
              title: 'Foreground color',
              description: 'Override the terminal text color.',
              value: overrides.foreground,
              fallback: '#f5f5f5',
              onChanged: (value) => onChanged(
                settings.copyWith(
                  colorOverrides: overrides.copyWith(foreground: value),
                ),
              ),
            ),
            _HexColorSettingRow(
              title: 'Background color',
              description: 'Override the terminal background color.',
              value: overrides.background,
              fallback: '#101010',
              onChanged: (value) => onChanged(
                settings.copyWith(
                  colorOverrides: overrides.copyWith(background: value),
                ),
              ),
            ),
            _HexColorSettingRow(
              title: 'Cursor color',
              description: 'Override the terminal cursor color.',
              value: overrides.cursor,
              fallback: '#e0e0e0',
              onChanged: (value) => onChanged(
                settings.copyWith(
                  colorOverrides: overrides.copyWith(cursor: value),
                ),
              ),
            ),
            _HexColorSettingRow(
              title: 'Selection color',
              description: 'Override the terminal selection color.',
              value: overrides.selection,
              fallback: '#3e4451',
              onChanged: (value) => onChanged(
                settings.copyWith(
                  colorOverrides: overrides.copyWith(selection: value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        _SettingsGroup(
          title: 'Advanced',
          description:
              'History, detached host lifetime and double-click selection behavior.',
          children: <Widget>[
            _IntegerSettingRow(
              title: 'Scrollback lines',
              description: 'Maximum terminal history retained per session.',
              value: settings.scrollbackLines,
              min: 100,
              max: 200000,
              step: 100,
              onChanged: (value) =>
                  onChanged(settings.copyWith(scrollbackLines: value)),
            ),
            _IntegerSettingRow(
              title: 'Host scrollback size',
              description:
                  'Maximum host-side terminal output retained per session.',
              value: settings.hostScrollbackBytes ~/ (1000 * 1000),
              min: 1,
              max: 256,
              step: 1,
              suffix: 'MB',
              onChanged: (value) => onChanged(
                settings.copyWith(hostScrollbackBytes: value * 1000 * 1000),
              ),
            ),
            _IntegerSettingRow(
              title: 'Empty host shutdown',
              description:
                  'Seconds to keep the host alive after the app closes with no running sessions.',
              value: settings.hostEmptyShutdownDelaySeconds,
              min: 5,
              max: 3600,
              step: 5,
              suffix: 's',
              onChanged: (value) => onChanged(
                settings.copyWith(hostEmptyShutdownDelaySeconds: value),
              ),
            ),
            _IntegerSettingRow(
              title: 'Detached session shutdown',
              description:
                  'Seconds to keep detached running sessions alive after the app closes.',
              value: settings.hostDetachedSessionShutdownDelaySeconds,
              min: 5,
              max: 86400,
              step: 60,
              suffix: 's',
              onChanged: (value) => onChanged(
                settings.copyWith(
                  hostDetachedSessionShutdownDelaySeconds: value,
                ),
              ),
            ),
            _TextSettingRow(
              title: 'Word separators',
              description: 'Characters that break double-click word selection.',
              value: settings.wordSeparators ?? '',
              trimValue: false,
              hintText: " ()[]{},\"'`",
              onChanged: (value) => onChanged(
                settings.copyWith(wordSeparators: value.isEmpty ? null : value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
