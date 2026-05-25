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
import 'package:alera/src/features/keyboard/presentation/keyboard_settings_pane.dart';
import 'package:alera/src/features/settings/application/github_star_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/features/updater/presentation/update_settings_section.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

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

const List<_SettingsSearchEntry> _terminalSearchEntries =
    <_SettingsSearchEntry>[
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

List<String> _filterOrdered(
  Iterable<String> values,
  String query, {
  int? limit,
}) {
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
  if (limit == null || matches.length <= limit) {
    return matches;
  }
  return matches.take(limit).toList(growable: false);
}

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
        onTap: onTap,
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
                    onPressed: () => section.onReset!(),
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

class _GeneralSettingsPane extends ConsumerWidget {
  const _GeneralSettingsPane({required this.general});

  final GeneralSettings general;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starState = ref.watch(gitHubStarControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AleraPanel(
          children: <Widget>[
            _WorkspaceDirectoryRow(
              value: general.workspaceDirectory,
              onChanged: (next) => ref
                  .read(settingsControllerProvider.notifier)
                  .updateWorkspaceDirectory(next),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        _SettingsGroup(
          title: 'Safety',
          description:
              'Confirmation prompts for destructive workspace actions.',
          children: <Widget>[
            _SwitchSettingRow(
              title: 'Confirm project removal',
              description:
                  'Ask before unregistering a project and deleting its workspace metadata.',
              value: general.confirmProjectRemoval,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setConfirmProjectRemoval(value),
            ),
            _SwitchSettingRow(
              title: 'Confirm workspace removal',
              description:
                  'Ask before removing a linked workspace and deleting its branch.',
              value: general.confirmWorkspaceRemoval,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setConfirmWorkspaceRemoval(value),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space24),
        const UpdateSettingsSection(),
        if (starState != GitHubStarState.hidden) ...<Widget>[
          const SizedBox(height: AleraTokens.space24),
          _SupportAleraSection(state: starState),
        ],
      ],
    );
  }
}

class _SupportAleraSection extends ConsumerWidget {
  const _SupportAleraSection({required this.state});

  final GitHubStarState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AleraTokens.space4,
            bottom: AleraTokens.space8,
          ),
          child: Text(
            'Support Alera',
            style: theme.textTheme.titleSmall?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        AleraPanel(
          children: <Widget>[
            AleraSettingRow(
              title: 'Star Alera on GitHub',
              description: null,
              child: _StarControl(
                state: state,
                onStar: () =>
                    ref.read(gitHubStarControllerProvider.notifier).star(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StarControl extends StatelessWidget {
  const _StarControl({required this.state, required this.onStar});

  final GitHubStarState state;
  final VoidCallback onStar;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedSwitcher(
        duration: AleraTokens.durationMid,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _buildChild(),
      ),
    );
  }

  Widget _buildChild() {
    switch (state) {
      case GitHubStarState.loading:
        return const _StarSkeleton(key: ValueKey<String>('loading'));
      case GitHubStarState.notStarred:
        return _StarButton(
          key: const ValueKey<String>('not-starred'),
          label: 'Star',
          onPressed: onStar,
        );
      case GitHubStarState.starring:
        return const _StarButton(
          key: ValueKey<String>('starring'),
          label: 'Starring…',
          busy: true,
        );
      case GitHubStarState.starred:
        return const _StarThanks(key: ValueKey<String>('starred'));
      case GitHubStarState.error:
        return _StarButton(
          key: const ValueKey<String>('error'),
          label: 'Try again',
          onPressed: onStar,
        );
      case GitHubStarState.hidden:
        return const SizedBox.shrink(key: ValueKey<String>('hidden'));
    }
  }
}

class _StarButton extends StatelessWidget {
  const _StarButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kSupportControlHeight,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AleraTokens.foreground,
                ),
              )
            : const Icon(Icons.star_outline, size: 16),
        label: Text(label),
      ),
    );
  }
}

class _StarThanks extends StatelessWidget {
  const _StarThanks({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Thanks for starring Alera',
      liveRegion: true,
      child: SizedBox(
        height: _kSupportControlHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.star, size: 16, color: AleraTokens.warning),
            const SizedBox(width: AleraTokens.space6),
            Text(
              'Thanks for the support!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarSkeleton extends StatelessWidget {
  const _StarSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kSupportControlHeight,
      width: 110,
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      ),
    );
  }
}

class _WorkspaceDirectoryRow extends StatefulWidget {
  const _WorkspaceDirectoryRow({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  State<_WorkspaceDirectoryRow> createState() => _WorkspaceDirectoryRowState();
}

class _WorkspaceDirectoryRowState extends State<_WorkspaceDirectoryRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(_WorkspaceDirectoryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        (widget.value ?? '') != _controller.text) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final next = _controller.text.trim();
    if (next.isEmpty) {
      if (widget.value != null) {
        widget.onChanged(null);
      }
      return;
    }
    if (next != widget.value) {
      widget.onChanged(next);
    }
  }

  Future<void> _browse() async {
    final picked = await getDirectoryPath(
      initialDirectory: _controller.text.isNotEmpty
          ? _controller.text
          : widget.value,
      confirmButtonText: 'Use as workspace directory',
    );
    if (picked == null) {
      return;
    }
    _controller.text = picked;
    widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Workspace directory',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            'Where new linked workspaces are created on disk. Existing '
            'workspaces are not moved. Leave empty to use the default '
            '(~/.alera/workspaces).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: AleraTextField(
                  controller: _controller,
                  onSubmitted: (_) => _commit(),
                  onEditingComplete: _commit,
                  hintText: '~/.alera/workspaces',
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              OutlinedButton.icon(
                onPressed: _browse,
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('Browse'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
          description: 'History and double-click selection behavior.',
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
            _TextSettingRow(
              title: 'Word separators',
              description: 'Characters that break double-click word selection.',
              value: settings.wordSeparators ?? '',
              allowEmpty: true,
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

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AleraTokens.space4,
            bottom: AleraTokens.space8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AleraTokens.space4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
        ),
        AleraPanel(children: children),
      ],
    );
  }
}

class _TextSettingRow extends StatefulWidget {
  const _TextSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.allowEmpty = false,
    this.hintText,
    this.trimValue = true,
  });

  final String title;
  final String description;
  final String value;
  final ValueChanged<String> onChanged;
  final bool allowEmpty;
  final String? hintText;
  final bool trimValue;

  @override
  State<_TextSettingRow> createState() => _TextSettingRowState();
}

class _TextSettingRowState extends State<_TextSettingRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final value = widget.trimValue ? _controller.text.trim() : _controller.text;
    if (value.isEmpty && !widget.allowEmpty) {
      _controller.text = widget.value;
      return;
    }
    if (value != widget.value) {
      widget.onChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: widget.title,
      description: widget.description,
      child: AleraTextField(
        controller: _controller,
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
        hintText: widget.hintText,
      ),
    );
  }
}

class _FontAutocompleteSettingRow extends StatefulWidget {
  const _FontAutocompleteSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.suggestions,
    required this.onChanged,
  });

  final String title;
  final String description;
  final String value;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;

  @override
  State<_FontAutocompleteSettingRow> createState() =>
      _FontAutocompleteSettingRowState();
}

class _FontAutocompleteSettingRowState
    extends State<_FontAutocompleteSettingRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _open = false;
  int _highlightedIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode(debugLabel: 'TerminalFontFamily');
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(_FontAutocompleteSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        widget.value != oldWidget.value &&
        widget.value != _controller.text) {
      _controller.text = widget.value;
    }
    if (widget.suggestions != oldWidget.suggestions) {
      _syncHighlightedIndex();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<String> get _filteredSuggestions {
    return _filterOrdered(widget.suggestions, _controller.text);
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      return;
    }
    Future<void>.delayed(AleraTokens.durationFast, () {
      if (!mounted || _focusNode.hasFocus) {
        return;
      }
      _commitValue(_controller.text);
    });
  }

  void _openMenu() {
    setState(() {
      _open = true;
      _syncHighlightedIndex();
    });
  }

  void _syncHighlightedIndex() {
    final suggestions = _filteredSuggestions;
    if (!_open || suggestions.isEmpty) {
      _highlightedIndex = -1;
      return;
    }
    final selectedIndex = suggestions.indexOf(widget.value);
    _highlightedIndex = selectedIndex >= 0 ? selectedIndex : 0;
  }

  void _commitValue(String value) {
    final next = value.trim();
    if (next.isEmpty) {
      _controller.text = widget.value;
      setState(() => _open = false);
      return;
    }
    _controller.text = next;
    if (next != widget.value) {
      widget.onChanged(next);
    }
    setState(() => _open = false);
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final suggestions = _filteredSuggestions;
    if (event.logicalKey == LogicalKeyboardKey.escape && _open) {
      setState(() => _open = false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _open = true;
        if (suggestions.isNotEmpty) {
          _highlightedIndex = _highlightedIndex < 0
              ? 0
              : (_highlightedIndex + 1).clamp(0, suggestions.length - 1);
        }
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _open = true;
        if (suggestions.isNotEmpty) {
          _highlightedIndex = _highlightedIndex < 0
              ? suggestions.length - 1
              : (_highlightedIndex - 1).clamp(0, suggestions.length - 1);
        }
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_open &&
          _highlightedIndex >= 0 &&
          _highlightedIndex < suggestions.length) {
        _commitValue(suggestions[_highlightedIndex]);
      } else {
        _commitValue(_controller.text);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _filteredSuggestions;
    return AleraSettingRow(
      title: widget.title,
      description: widget.description,
      child: Focus(
        onKeyEvent: _handleKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AleraTextField(
              key: const ValueKey<String>('terminal-font-family-field'),
              controller: _controller,
              focusNode: _focusNode,
              onTap: _openMenu,
              onChanged: (value) {
                setState(() {
                  _open = true;
                  _syncHighlightedIndex();
                });
              },
              onSubmitted: _commitValue,
              onEditingComplete: () => _commitValue(_controller.text),
              hintText: 'SF Mono',
              suffix: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_controller.text.isNotEmpty)
                    AleraIconButton(
                      tooltip: 'Clear',
                      icon: Icons.cancel_outlined,
                      iconSize: 16,
                      minSize: 28,
                      onPressed: () {
                        _controller.clear();
                        _openMenu();
                        _focusNode.requestFocus();
                      },
                    ),
                  AleraIconButton(
                    tooltip: 'Fonts',
                    icon: _open ? Icons.expand_less : Icons.expand_more,
                    iconSize: 18,
                    minSize: 28,
                    onPressed: () {
                      setState(() {
                        _open = !_open;
                        _syncHighlightedIndex();
                      });
                      _focusNode.requestFocus();
                    },
                  ),
                ],
              ),
            ),
            if (_open) ...<Widget>[
              const SizedBox(height: AleraTokens.space6),
              _AutocompleteMenu(
                emptyText: 'No matching fonts.',
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final font = suggestions[index];
                  final active = index == _highlightedIndex;
                  final selected = font == widget.value;
                  return AleraMenuItem(
                    label: font,
                    active: active,
                    selected: selected,
                    onHover: () => setState(() => _highlightedIndex = index),
                    onTap: () => _commitValue(font),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AutocompleteMenu extends StatelessWidget {
  const _AutocompleteMenu({
    required this.emptyText,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String emptyText;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: AleraTokens.shadowSoft,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _kPickerMenuMaxHeight),
        child: itemCount == 0
            ? AleraEmptyState(message: emptyText)
            : ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  vertical: AleraTokens.space4,
                ),
                itemCount: itemCount,
                itemBuilder: itemBuilder,
              ),
      ),
    );
  }
}

class _NumberSettingRow extends StatelessWidget {
  const _NumberSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.suffix,
  });

  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final double step;
  final String? suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: title,
      description: description,
      child: AleraNumberField(
        value: value,
        min: min,
        max: max,
        step: step,
        suffix: suffix,
        onChanged: onChanged,
      ),
    );
  }
}

class _IntegerSettingRow extends StatelessWidget {
  const _IntegerSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String title;
  final String description;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: title,
      description: description,
      child: AleraNumberField(
        value: value.toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        step: step.toDouble(),
        onChanged: (value) => onChanged(value.round()),
      ),
    );
  }
}

class _SwitchSettingRow extends StatelessWidget {
  const _SwitchSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: title,
      description: description,
      child: Align(
        alignment: Alignment.centerRight,
        child: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

class _ThemePickerSetting extends StatefulWidget {
  const _ThemePickerSetting({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_ThemePickerSetting> createState() => _ThemePickerSettingState();
}

class _ThemePickerSettingState extends State<_ThemePickerSetting> {
  final TextEditingController _controller = TextEditingController();
  int _highlightedIndex = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<TerminalThemeEntry> get _filteredThemes {
    final names = _filterOrdered(
      terminalThemeNames,
      _controller.text,
      limit: terminalThemeNames.length,
    );
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Theme preset',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: FontWeight.w500,
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    searchAndList,
                    const SizedBox(height: AleraTokens.space12),
                    _TerminalThemePreview(entry: selected),
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

class _ThemeSearchList extends StatelessWidget {
  const _ThemeSearchList({
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
  final List<TerminalThemeEntry> themes;
  final int highlightedIndex;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<int> onHoverTheme;
  final ValueChanged<TerminalThemeEntry> onSelectTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      overflow: TextOverflow.ellipsis,
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

class _ThemeColorDots extends StatelessWidget {
  const _ThemeColorDots({required this.entry});

  final TerminalThemeEntry entry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 12,
      child: Row(
        children: <Widget>[
          _ThemeColorDot(color: entry.theme.red),
          _ThemeColorDot(color: entry.theme.green),
          _ThemeColorDot(color: entry.theme.blue),
        ],
      ),
    );
  }
}

class _ThemeColorDot extends StatelessWidget {
  const _ThemeColorDot({required this.color});

  final Color color;

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

class _TerminalThemePreview extends StatelessWidget {
  const _TerminalThemePreview({required this.entry});

  final TerminalThemeEntry entry;

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
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    overflow: TextOverflow.ellipsis,
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
              overflow: TextOverflow.ellipsis,
              style: monoStyle?.copyWith(color: terminalTheme.red),
            ),
            Text(
              'A  lib/src/features/settings/domain/terminal_theme_catalog.dart',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
              mainAxisSize: MainAxisSize.min,
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

class _HexColorSettingRow extends StatefulWidget {
  const _HexColorSettingRow({
    required this.title,
    required this.description,
    required this.value,
    required this.fallback,
    required this.onChanged,
  });

  final String title;
  final String description;
  final String? value;
  final String fallback;
  final ValueChanged<String?> onChanged;

  @override
  State<_HexColorSettingRow> createState() => _HexColorSettingRowState();
}

class _HexColorSettingRowState extends State<_HexColorSettingRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(_HexColorSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value ?? '';
    if (next != oldWidget.value && next != _controller.text) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      if (widget.value != null) {
        widget.onChanged(null);
      }
      _controller.text = '';
      return;
    }

    final normalized = normalizeTerminalHexColor(raw);
    if (normalized == null) {
      _controller.text = widget.value ?? '';
      return;
    }
    _controller.text = normalized;
    if (normalized != widget.value) {
      widget.onChanged(normalized);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: widget.title,
      description: widget.description,
      child: Row(
        children: <Widget>[
          AleraColorSwatch(
            color: _colorFromHex(widget.value ?? widget.fallback),
            pickerTitle: widget.title,
            onColorChanged: (selectedColor) {
              if (!mounted) return;
              final r = (selectedColor.r * 255).round().toRadixString(16).padLeft(2, '0');
              final g = (selectedColor.g * 255).round().toRadixString(16).padLeft(2, '0');
              final b = (selectedColor.b * 255).round().toRadixString(16).padLeft(2, '0');
              final hex = '#$r$g$b';
              _controller.text = hex;
              _commit();
            },
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: AleraTextField(
              controller: _controller,
              onSubmitted: (_) => _commit(),
              onEditingComplete: _commit,
              hintText: widget.fallback,
            ),
          ),
        ],
      ),
    );
  }
}

class _CursorShapeRow extends StatelessWidget {
  const _CursorShapeRow({required this.value, required this.onChanged});

  final TerminalCursorShape value;
  final ValueChanged<TerminalCursorShape> onChanged;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: 'Cursor shape',
      description: 'Cursor style for new terminal sessions.',
      child: AleraSegmentedButton<TerminalCursorShape>(
        selected: value,
        onSelectionChanged: onChanged,
        segments: const <ButtonSegment<TerminalCursorShape>>[
          ButtonSegment<TerminalCursorShape>(
            value: TerminalCursorShape.block,
            tooltip: 'Block',
            icon: _CursorGlyph(shape: TerminalCursorShape.block),
          ),
          ButtonSegment<TerminalCursorShape>(
            value: TerminalCursorShape.bar,
            tooltip: 'Bar',
            icon: _CursorGlyph(shape: TerminalCursorShape.bar),
          ),
          ButtonSegment<TerminalCursorShape>(
            value: TerminalCursorShape.underline,
            tooltip: 'Underline',
            icon: _CursorGlyph(shape: TerminalCursorShape.underline),
          ),
        ],
      ),
    );
  }
}

class _CursorGlyph extends StatelessWidget {
  const _CursorGlyph({required this.shape});

  final TerminalCursorShape shape;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final color = iconTheme.color ?? AleraTokens.foreground;
    final size = iconTheme.size ?? _kSidebarIconSize;
    final Widget glyph;
    Alignment alignment = Alignment.center;
    switch (shape) {
      case TerminalCursorShape.block:
        glyph = Container(
          width: size * 0.45,
          height: size * 0.72,
          color: color,
        );
        break;
      case TerminalCursorShape.bar:
        glyph = Container(width: 2, height: size * 0.72, color: color);
        break;
      case TerminalCursorShape.underline:
        glyph = Container(width: size * 0.6, height: 2, color: color);
        alignment = Alignment.bottomCenter;
        break;
    }
    return SizedBox(
      width: size,
      height: size,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: shape == TerminalCursorShape.underline
              ? const EdgeInsets.only(bottom: 2)
              : EdgeInsets.zero,
          child: glyph,
        ),
      ),
    );
  }
}

Color _colorFromHex(String value) {
  final normalized = normalizeTerminalHexColor(value) ?? '#000000';
  return Color(0xFF000000 | int.parse(normalized.substring(1), radix: 16));
}

class _NoSettingsResults extends StatelessWidget {
  const _NoSettingsResults({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(
          child: AleraEmptyState(message: 'No settings found.'),
        ),
        Positioned(
          top: AleraTokens.space16,
          right: AleraTokens.space16,
          child: AleraIconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: Icons.close,
            minSize: 28,
          ),
        ),
      ],
    );
  }
}
