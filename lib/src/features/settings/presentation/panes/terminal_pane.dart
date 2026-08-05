import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/presentation/panes/terminal_theme_controls.dart';
import 'package:alera/src/features/settings/presentation/panes/terminal_theme_picker.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_font_autocomplete_row.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';

class TerminalSettingsPane extends StatelessWidget {
  const TerminalSettingsPane({
    super.key,
    required this.settings,
    required this.fontSuggestions,
    required this.onChanged,
    this.onReloadShellEnvironment,
    this.groupKeys = const <String, GlobalKey>{},
  });

  final TerminalSettings settings;
  final List<String> fontSuggestions;
  final ValueChanged<TerminalSettings> onChanged;

  /// Re-probes the login shell so a tool installed mid-session resolves without
  /// restarting the runtime. When null the row is omitted.
  final Future<void> Function()? onReloadShellEnvironment;
  final Map<String, GlobalKey> groupKeys;

  @override
  Widget build(BuildContext context) {
    final overrides = settings.colorOverrides;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeyedSubtree(
          key: groupKeys['typography'],
          child: AleraSettingsGroup(
            title: 'Typography',
            description: 'Default terminal typography for new sessions.',
            children: <Widget>[
              SettingsFontAutocompleteRow(
                title: 'Font Family',
                description: 'Typeface used in new terminal sessions.',
                value: settings.fontFamily,
                suggestions: fontSuggestions,
                onChanged: (value) =>
                    onChanged(settings.copyWith(fontFamily: value)),
              ),
              SettingsNumberRow(
                title: 'Font Size',
                description: 'Text size used in new terminal sessions.',
                value: settings.fontSize,
                min: 8,
                max: 32,
                step: 1,
                suffix: 'px',
                onChanged: (value) =>
                    onChanged(settings.copyWith(fontSize: value)),
              ),
              SettingsIntegerRow(
                title: 'Font Weight',
                description: 'Weight used for terminal text.',
                value: settings.fontWeight,
                min: 100,
                max: 900,
                step: 100,
                onChanged: (value) =>
                    onChanged(settings.copyWith(fontWeight: value)),
              ),
              SettingsNumberRow(
                title: 'Line Height',
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
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: groupKeys['cursor'],
          child: AleraSettingsGroup(
            title: 'Cursor',
            description: 'Default cursor appearance for terminal sessions.',
            children: <Widget>[
              CursorShapeRow(
                value: settings.cursorShape,
                onChanged: (value) =>
                    onChanged(settings.copyWith(cursorShape: value)),
              ),
              SettingsSwitchRow(
                title: 'Blinking Cursor',
                description: 'Blink the cursor while the terminal has focus.',
                value: settings.cursorBlink,
                onChanged: (value) =>
                    onChanged(settings.copyWith(cursorBlink: value)),
              ),
              SettingsNumberRow(
                title: 'Cursor Opacity',
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
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: groupKeys['appearance'],
          child: AleraSettingsGroup(
            title: 'Appearance',
            description: 'Terminal colors, theme and spacing.',
            children: <Widget>[
              ThemePickerSetting(
                value: settings.themeName,
                onChanged: (value) =>
                    onChanged(settings.copyWith(themeName: value)),
              ),
              SettingsNumberRow(
                title: 'Background Opacity',
                description: 'Opacity of the terminal background.',
                value: settings.backgroundOpacity,
                min: 0,
                max: 1,
                step: 0.05,
                onChanged: (value) =>
                    onChanged(settings.copyWith(backgroundOpacity: value)),
              ),
              SettingsNumberRow(
                title: 'Horizontal Padding',
                description: 'Horizontal spacing around the terminal grid.',
                value: settings.paddingX,
                min: 0,
                max: 64,
                step: 1,
                suffix: 'px',
                onChanged: (value) =>
                    onChanged(settings.copyWith(paddingX: value)),
              ),
              SettingsNumberRow(
                title: 'Vertical Padding',
                description: 'Vertical spacing around the terminal grid.',
                value: settings.paddingY,
                min: 0,
                max: 64,
                step: 1,
                suffix: 'px',
                onChanged: (value) =>
                    onChanged(settings.copyWith(paddingY: value)),
              ),
              HexColorSettingRow(
                title: 'Foreground Color',
                description: 'Override the terminal text color.',
                value: overrides.foreground,
                fallback: '#f5f5f5',
                onChanged: (value) => onChanged(
                  settings.copyWith(
                    colorOverrides: overrides.copyWith(foreground: value),
                  ),
                ),
              ),
              HexColorSettingRow(
                title: 'Background Color',
                description: 'Override the terminal background color.',
                value: overrides.background,
                fallback: '#101010',
                onChanged: (value) => onChanged(
                  settings.copyWith(
                    colorOverrides: overrides.copyWith(background: value),
                  ),
                ),
              ),
              HexColorSettingRow(
                title: 'Cursor Color',
                description: 'Override the terminal cursor color.',
                value: overrides.cursor,
                fallback: '#e0e0e0',
                onChanged: (value) => onChanged(
                  settings.copyWith(
                    colorOverrides: overrides.copyWith(cursor: value),
                  ),
                ),
              ),
              HexColorSettingRow(
                title: 'Selection Color',
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
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: groupKeys['interaction'],
          child: AleraSettingsGroup(
            title: 'Interaction',
            description: 'Mouse, scrolling and clipboard behavior for TUIs.',
            children: <Widget>[
              SettingsIntegerRow(
                title: 'TUI Scroll Speed',
                description:
                    'Mouse reports sent per wheel step while a TUI owns scrolling.',
                value: settings.tuiScrollSensitivity,
                min: 1,
                max: 10,
                step: 1,
                onChanged: (value) =>
                    onChanged(settings.copyWith(tuiScrollSensitivity: value)),
              ),
              SettingsSwitchRow(
                title: 'Copy On Select',
                description:
                    'Copy local terminal selections to the system clipboard.',
                value: settings.clipboardOnSelect,
                onChanged: (value) =>
                    onChanged(settings.copyWith(clipboardOnSelect: value)),
              ),
              SettingsSwitchRow(
                title: 'Allow OSC 52 Clipboard Writes',
                description:
                    'Let terminal applications replace the system clipboard.',
                value: settings.allowOsc52Clipboard,
                onChanged: (value) =>
                    onChanged(settings.copyWith(allowOsc52Clipboard: value)),
              ),
              SettingsSwitchRow(
                title: 'Show Terminal Composer By Default',
                description:
                    'Open the prompt composer when a new terminal session starts.',
                value: settings.showComposerByDefault,
                onChanged: (value) =>
                    onChanged(settings.copyWith(showComposerByDefault: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: groupKeys['advanced'],
          child: AleraSettingsGroup(
            title: 'Advanced',
            description:
                'History, shell startup and double-click selection behavior.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Use Login Shell',
                description:
                    'Start shells as login shells so profile files such as ~/.zprofile and ~/.profile are loaded.',
                value: settings.resolvedLoginShell,
                onChanged: (value) =>
                    onChanged(settings.copyWith(loginShell: value)),
              ),
              if (onReloadShellEnvironment != null)
                SettingsButtonRow(
                  title: 'Reload Shell Environment',
                  description:
                      'Re-read the login shell PATH so tools installed since the runtime started resolve in new terminals.',
                  buttonLabel: 'Reload',
                  onPressed: onReloadShellEnvironment,
                ),
              SettingsIntegerRow(
                title: 'Scrollback Lines',
                description: 'Maximum terminal history retained per session.',
                value: settings.scrollbackLines,
                min: 100,
                max: 200000,
                step: 100,
                onChanged: (value) =>
                    onChanged(settings.copyWith(scrollbackLines: value)),
              ),
              SettingsIntegerRow(
                title: 'Host Scrollback Size',
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
              SettingsIntegerRow(
                title: 'Terminal Memory Budget',
                description:
                    'Ceiling for terminal scrollback held in the app. Over it, '
                    'terminals you have not looked at recently are unloaded '
                    'and restored when you return. Their agents keep running. '
                    'Only panes currently on screen stay loaded over it. '
                    'Use 0 for no limit.',
                value: settings.bufferBudgetMegabytes,
                min: 0,
                max: 4096,
                step: 64,
                suffix: 'MB',
                onChanged: (value) =>
                    onChanged(settings.copyWith(bufferBudgetMegabytes: value)),
              ),
              SettingsTextRow(
                title: 'Word Separators',
                description:
                    'Characters that break double-click word selection.',
                value: settings.wordSeparators ?? '',
                trimValue: false,
                hintText: " ()[]{},\"'`",
                onChanged: (value) => onChanged(
                  settings.copyWith(
                    wordSeparators: value.isEmpty ? null : value,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
