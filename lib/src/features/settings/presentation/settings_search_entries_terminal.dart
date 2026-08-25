import 'package:alera/src/features/settings/presentation/settings_sections.dart';

// Search entries for the Terminal pane. Split out of
// `settings_search_entries.dart` to keep both files under the size limit;
// the terminal pane alone carries more preferences than any other.

const List<SettingsSearchEntry> terminalSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry(
    title: 'Font Family',
    description: 'Typeface used in new terminal sessions.',
    keywords: <String>['monospace', 'jetbrains', 'typeface'],
    groupId: 'typography',
  ),
  SettingsSearchEntry(
    title: 'Font Size',
    description: 'Text size used in new terminal sessions.',
    keywords: <String>['terminal text', 'zoom'],
    groupId: 'typography',
  ),
  SettingsSearchEntry(
    title: 'Font Weight',
    description: 'Weight used for terminal text.',
    keywords: <String>['terminal text', 'bold'],
    groupId: 'typography',
  ),
  SettingsSearchEntry(
    title: 'Line Height',
    description: 'Vertical spacing for terminal rows.',
    keywords: <String>['spacing', 'rows'],
    groupId: 'typography',
  ),
  SettingsSearchEntry(
    title: 'Theme Preset',
    description: 'Built-in terminal color theme.',
    keywords: <String>['color', 'appearance', 'palette'],
    groupId: 'appearance',
  ),
  SettingsSearchEntry(
    title: 'Background Opacity',
    description: 'Opacity of the terminal background.',
    keywords: <String>['transparent', 'alpha'],
    groupId: 'appearance',
  ),
  SettingsSearchEntry(
    title: 'Horizontal Padding',
    description: 'Horizontal spacing around the terminal grid.',
    keywords: <String>['inset', 'space'],
    groupId: 'appearance',
  ),
  SettingsSearchEntry(
    title: 'Vertical Padding',
    description: 'Vertical spacing around the terminal grid.',
    keywords: <String>['inset', 'space'],
    groupId: 'appearance',
  ),
  SettingsSearchEntry(
    title: 'Toolbar Corner',
    description:
        'Where the pulse, composer, and refresh buttons sit on the terminal tab.',
    keywords: <String>['buttons', 'overlay', 'position', 'corner', 'move'],
    groupId: 'appearance',
  ),
  SettingsSearchEntry(
    title: 'Cursor Shape',
    description: 'Cursor style for new terminal sessions.',
    keywords: <String>['caret', 'block', 'bar', 'underline'],
    groupId: 'cursor',
  ),
  SettingsSearchEntry(
    title: 'Blinking Cursor',
    description: 'Blink the terminal cursor while focused.',
    keywords: <String>['caret', 'blink'],
    groupId: 'cursor',
  ),
  SettingsSearchEntry(
    title: 'Cursor Opacity',
    description: 'Opacity of the terminal cursor.',
    keywords: <String>['caret', 'alpha'],
    groupId: 'cursor',
  ),
  SettingsSearchEntry(
    title: 'Color Overrides',
    description: 'Override core terminal colors.',
    keywords: <String>['foreground', 'background', 'selection', 'cursor'],
    groupId: 'appearance',
  ),
  SettingsSearchEntry(
    title: 'TUI Scroll Speed',
    description: 'Mouse wheel speed for interactive terminal applications.',
    keywords: <String>['mouse', 'wheel', 'opencode', 'amp', 'claude'],
    groupId: 'interaction',
  ),
  SettingsSearchEntry(
    title: 'Copy On Select',
    description: 'Copy local terminal selections automatically.',
    keywords: <String>['clipboard', 'selection', 'mouse'],
    groupId: 'interaction',
  ),
  SettingsSearchEntry(
    title: 'Allow OSC 52 Clipboard Writes',
    description: 'Allow terminal applications to replace the clipboard.',
    keywords: <String>['clipboard', 'tui', 'ssh', 'tmux', 'osc52'],
    groupId: 'interaction',
  ),
  SettingsSearchEntry(
    title: 'Show Terminal Composer By Default',
    description: 'Open the prompt composer when a new terminal session starts.',
    keywords: <String>['composer', 'prompt', 'input', 'default'],
    groupId: 'interaction',
  ),
  SettingsSearchEntry(
    title: 'Scrollback Lines',
    description: 'Maximum terminal history retained per session.',
    keywords: <String>['history', 'buffer'],
    groupId: 'advanced',
  ),
  SettingsSearchEntry(
    title: 'Host Scrollback Size',
    description: 'Maximum host-side terminal output retained per session.',
    keywords: <String>['history', 'buffer', 'memory', 'host'],
    groupId: 'advanced',
  ),
  SettingsSearchEntry(
    title: 'Word Separators',
    description: 'Characters that break double-click word selection.',
    keywords: <String>['boundary', 'selection', 'double click'],
    groupId: 'advanced',
  ),
];
