import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_color_swatch.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_number_field.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_settings_pane.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/features/updater/presentation/update_settings_section.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

part 'settings_dialog_navigation.dart';
part 'settings_dialog_general_pane.dart';
part 'settings_dialog_editor_pane.dart';
part 'settings_dialog_terminal_pane.dart';
part 'settings_dialog_theme_picker.dart';
part 'settings_dialog_setting_rows.dart';
part 'settings_dialog_theme_controls.dart';

const double _kDialogMaxWidth = 920;
const double _kDialogMaxHeight = 680;
const double _kSidebarWidth = 260;
const double _kSidebarIconSize = 16;
const double _kSectionIconSize = 18;
const double _kSupportControlHeight = 34;
const double _kPickerMenuMaxHeight = 220;

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _activeSectionId = 'general';
  late List<String> _fontSuggestions = fallbackTerminalFontFamilies();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text.trim().toLowerCase();
      if (next != _query) {
        setState(() => _query = next);
      }
    });
    _loadFontSuggestions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFontSuggestions() async {
    final fonts = await ref.read(systemFontServiceProvider).listFontFamilies();
    if (!mounted || fonts.isEmpty) {
      return;
    }
    setState(() {
      _fontSuggestions = _mergeFontSuggestions(fonts);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    final sections = <_SettingsSectionData>[
      _SettingsSectionData(
        id: 'general',
        title: 'General',
        description: 'Storage and integrations.',
        icon: Icons.tune,
        entries: _generalSearchEntries,
        builder: (_) => _GeneralSettingsPane(general: settings.general),
      ),
      _SettingsSectionData(
        id: 'editor',
        title: 'Editor',
        description: 'Code editor defaults.',
        icon: Icons.code,
        entries: _editorSearchEntries,
        onReset: controller.resetEditorSettings,
        builder: (_) => _EditorSettingsPane(
          settings: settings.editor,
          onChanged: (editor) => controller.updateEditor(editor),
        ),
      ),
      _SettingsSectionData(
        id: 'terminal',
        title: 'Terminal',
        description: 'Appearance defaults for new terminal sessions.',
        icon: Icons.terminal,
        entries: _terminalSearchEntries,
        onReset: controller.resetTerminalSettings,
        builder: (_) => _TerminalSettingsPane(
          settings: settings.terminal,
          fontSuggestions: _fontSuggestions,
          onChanged: (terminal) => controller.updateTerminal(terminal),
        ),
      ),
      _SettingsSectionData(
        id: 'keyboard',
        title: 'Keyboard',
        description: 'Shortcuts and key bindings.',
        icon: Icons.keyboard,
        entries: _keyboardSearchEntries,
        onReset: controller.resetKeyboardShortcuts,
        builder: (_) => const KeyboardSettingsPane(),
      ),
    ];

    final visibleSections = sections
        .where((section) => section.matches(_query))
        .toList();

    final activeSection = visibleSections.isEmpty
        ? null
        : visibleSections.firstWhere(
            (section) => section.id == _activeSectionId,
            orElse: () => visibleSections.first,
          );

    return AleraDialog(
      maxWidth: _kDialogMaxWidth,
      maxHeight: _kDialogMaxHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SettingsSidebar(
            queryController: _searchController,
            visibleSections: visibleSections,
            activeSectionId: activeSection?.id,
            onSelect: (id) => setState(() => _activeSectionId = id),
          ),
          const VerticalDivider(width: 1, color: AleraTokens.borderSubtle),
          Expanded(
            child: activeSection != null
                ? _SettingsContent(
                    section: activeSection,
                    onClose: () => Navigator.of(context).pop(),
                  )
                : _NoSettingsResults(
                    onClose: () => Navigator.of(context).pop(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionData {
  const _SettingsSectionData({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.entries,
    required this.builder,
    this.onReset,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final List<_SettingsSearchEntry> entries;
  final WidgetBuilder builder;
  final Future<void> Function()? onReset;

  bool matches(String query) {
    if (query.isEmpty) {
      return true;
    }
    final sectionEntry = _SettingsSearchEntry(
      title: title,
      description: description,
    );
    return sectionEntry.matches(query) ||
        entries.any((entry) => entry.matches(query));
  }
}

class _SettingsSearchEntry {
  const _SettingsSearchEntry({
    required this.title,
    this.description,
    this.keywords = const <String>[],
  });

  final String title;
  final String? description;
  final List<String> keywords;

  bool matches(String query) {
    if (query.isEmpty) {
      return true;
    }
    return <String>[
      title,
      description ?? '',
      ...keywords,
    ].any((value) => value.toLowerCase().contains(query));
  }
}

const List<_SettingsSearchEntry> _generalSearchEntries = <_SettingsSearchEntry>[
  _SettingsSearchEntry(
    title: 'Workspace directory',
    description: 'Where new linked workspaces are created on disk.',
    keywords: <String>['worktree', 'folder', 'location', 'path'],
  ),
  _SettingsSearchEntry(
    title: 'Confirm project removal',
    description: 'Ask before unregistering a project.',
    keywords: <String>['safety', 'destructive', 'remove', 'delete'],
  ),
  _SettingsSearchEntry(
    title: 'Confirm workspace removal',
    description: 'Ask before removing a workspace worktree.',
    keywords: <String>['safety', 'destructive', 'remove', 'delete'],
  ),
  _SettingsSearchEntry(
    title: 'Codex hooks',
    description: 'Use Alera-managed Codex runtime hooks.',
    keywords: <String>['codex', 'agent', 'status', 'hooks'],
  ),
  _SettingsSearchEntry(
    title: 'Claude Code hooks',
    description: 'Use an Alera-managed Claude Code config with status hooks.',
    keywords: <String>['claude', 'agent', 'status', 'hooks'],
  ),
  _SettingsSearchEntry(
    title: 'GitHub Copilot hooks',
    description: 'Use an Alera-managed GitHub Copilot home overlay.',
    keywords: <String>['copilot', 'github', 'agent', 'status', 'hooks'],
  ),
  _SettingsSearchEntry(
    title: 'Cursor hooks',
    description: 'Use an Alera-managed Cursor Agent plugin wrapper.',
    keywords: <String>['cursor', 'agent', 'status', 'hooks', 'cli'],
  ),
  _SettingsSearchEntry(
    title: 'Antigravity hooks',
    description: 'Install managed Antigravity hooks for the agy CLI.',
    keywords: <String>['antigravity', 'agy', 'agent', 'status', 'hooks'],
  ),
  _SettingsSearchEntry(
    title: 'OpenCode hooks',
    description: 'Install managed OpenCode status plugin.',
    keywords: <String>['opencode', 'agent', 'status', 'hooks', 'plugin'],
  ),
  _SettingsSearchEntry(
    title: 'Pi hooks',
    description: 'Install managed Pi status extension.',
    keywords: <String>['pi', 'agent', 'status', 'hooks', 'extension'],
  ),
  _SettingsSearchEntry(
    title: 'Amp hooks',
    description: 'Use an Alera-managed Amp config overlay.',
    keywords: <String>['amp', 'agent', 'status', 'hooks', 'plugin'],
  ),
  _SettingsSearchEntry(
    title: 'Agent status notifications',
    description: 'Show native notifications when agents need attention.',
    keywords: <String>[
      'codex',
      'claude',
      'copilot',
      'cursor',
      'antigravity',
      'agy',
      'opencode',
      'pi',
      'amp',
      'agent',
      'status',
      'notification',
    ],
  ),
  _SettingsSearchEntry(
    title: 'Keep computer awake while agents are working',
    description: 'Keep this computer and display awake during agent work.',
    keywords: <String>[
      'awake',
      'sleep',
      'power',
      'agent',
      'working',
      'lid',
      'display',
    ],
  ),
  _SettingsSearchEntry(
    title: 'Updates',
    description: 'Check desktop releases for this platform.',
    keywords: <String>['release', 'download', 'version'],
  ),
  _SettingsSearchEntry(
    title: 'Star Alera on GitHub',
    description: 'Show your support for the project.',
    keywords: <String>['support', 'github', 'star'],
  ),
];

const List<_SettingsSearchEntry> _keyboardSearchEntries =
    <_SettingsSearchEntry>[
      _SettingsSearchEntry(
        title: 'Keyboard shortcuts',
        description: 'View and remap app-wide key bindings.',
        keywords: <String>[
          'shortcut',
          'hotkey',
          'keybinding',
          'binding',
          'keymap',
        ],
      ),
      _SettingsSearchEntry(
        title: 'Terminal shortcut behavior',
        description:
            'Choose whether app shortcuts win while a terminal is '
            'focused.',
        keywords: <String>['app first', 'terminal first', 'policy'],
      ),
    ];

const List<_SettingsSearchEntry> _editorSearchEntries = <_SettingsSearchEntry>[
  _SettingsSearchEntry(
    title: 'Theme preset',
    description: 'Syntax highlighting theme used by editor tabs.',
    keywords: <String>['syntax', 'highlight', 'highlighting', 'color', 'code'],
  ),
  _SettingsSearchEntry(
    title: 'Tab size',
    description: 'Spaces inserted when pressing Tab in editor tabs.',
    keywords: <String>['indent', 'indentation', 'spaces', 'code'],
  ),
];

const List<_SettingsSearchEntry>
_terminalSearchEntries = <_SettingsSearchEntry>[
  _SettingsSearchEntry(
    title: 'Font family',
    description: 'Typeface used in new terminal sessions.',
    keywords: <String>['monospace', 'jetbrains', 'typeface'],
  ),
  _SettingsSearchEntry(
    title: 'Font size',
    description: 'Text size used in new terminal sessions.',
    keywords: <String>['terminal text', 'zoom'],
  ),
  _SettingsSearchEntry(
    title: 'Font weight',
    description: 'Weight used for terminal text.',
    keywords: <String>['terminal text', 'bold'],
  ),
  _SettingsSearchEntry(
    title: 'Line height',
    description: 'Vertical spacing for terminal rows.',
    keywords: <String>['spacing', 'rows'],
  ),
  _SettingsSearchEntry(
    title: 'Theme preset',
    description: 'Built-in terminal color theme.',
    keywords: <String>['color', 'appearance', 'palette'],
  ),
  _SettingsSearchEntry(
    title: 'Background opacity',
    description: 'Opacity of the terminal background.',
    keywords: <String>['transparent', 'alpha'],
  ),
  _SettingsSearchEntry(
    title: 'Horizontal padding',
    description: 'Horizontal spacing around the terminal grid.',
    keywords: <String>['inset', 'space'],
  ),
  _SettingsSearchEntry(
    title: 'Vertical padding',
    description: 'Vertical spacing around the terminal grid.',
    keywords: <String>['inset', 'space'],
  ),
  _SettingsSearchEntry(
    title: 'Cursor shape',
    description: 'Cursor style for new terminal sessions.',
    keywords: <String>['caret', 'block', 'bar', 'underline'],
  ),
  _SettingsSearchEntry(
    title: 'Blinking cursor',
    description: 'Blink the terminal cursor while focused.',
    keywords: <String>['caret', 'blink'],
  ),
  _SettingsSearchEntry(
    title: 'Cursor opacity',
    description: 'Opacity of the terminal cursor.',
    keywords: <String>['caret', 'alpha'],
  ),
  _SettingsSearchEntry(
    title: 'Color overrides',
    description: 'Override core terminal colors.',
    keywords: <String>['foreground', 'background', 'selection', 'cursor'],
  ),
  _SettingsSearchEntry(
    title: 'Scrollback lines',
    description: 'Maximum terminal history retained per session.',
    keywords: <String>['history', 'buffer'],
  ),
  _SettingsSearchEntry(
    title: 'Host scrollback size',
    description: 'Maximum host-side terminal output retained per session.',
    keywords: <String>['history', 'buffer', 'memory', 'host'],
  ),
  _SettingsSearchEntry(
    title: 'Empty host shutdown',
    description:
        'Stop the terminal host after the app closes with no sessions.',
    keywords: <String>['host', 'sidecar', 'lifetime', 'timeout'],
  ),
  _SettingsSearchEntry(
    title: 'Detached session shutdown',
    description:
        'Stop detached running terminal sessions after the app stays closed.',
    keywords: <String>['host', 'sidecar', 'session', 'timeout'],
  ),
  _SettingsSearchEntry(
    title: 'Word separators',
    description: 'Characters that break double-click word selection.',
    keywords: <String>['boundary', 'selection', 'double click'],
  ),
];

List<String> _mergeFontSuggestions(List<String> fonts) {
  final byName = <String, String>{};
  for (final font in <String>[...fonts, ...fallbackTerminalFontFamilies()]) {
    final trimmed = font.trim();
    if (trimmed.isEmpty || trimmed.startsWith('.')) {
      continue;
    }
    byName.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
  }
  return byName.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

List<String> _filterOrdered(Iterable<String> values, String query) {
  final normalized = query.trim().toLowerCase();
  final matches = normalized.isEmpty
      ? values.toList(growable: false)
      : <String>[
          ...values.where(
            (value) => value.toLowerCase().startsWith(normalized),
          ),
          ...values.where((value) {
            final lower = value.toLowerCase();
            return !lower.startsWith(normalized) && lower.contains(normalized);
          }),
        ];
  return matches;
}
