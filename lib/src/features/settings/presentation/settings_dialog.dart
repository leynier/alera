import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_settings_pane.dart';
import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/features/settings/presentation/panes/agents_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_text_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/application_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/editor_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/projects_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_hosts_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/terminal_pane.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog_content.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog_sidebar.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The dialog fills most of the screen so the settings surface feels like a
// full window while still leaving a small breathing margin on large displays.
const double _kDialogWidthFraction = 0.92;
const double _kDialogHeightFraction = 0.92;
const double _kDialogMinWidth = 760;
const double _kDialogMaxWidth = 1800;
const double _kDialogMinHeight = 560;
const double _kDialogMaxHeight = 1280;

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Map<String, GlobalKey>> _groupKeys =
      <String, Map<String, GlobalKey>>{};
  String _query = '';
  String _activeSectionId = 'application';
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

  Map<String, GlobalKey> _keysFor(String sectionId) {
    return _groupKeys.putIfAbsent(sectionId, () => <String, GlobalKey>{});
  }

  GlobalKey _groupKey(String sectionId, String groupId) {
    return _keysFor(
      sectionId,
    ).putIfAbsent(groupId, () => GlobalKey(debugLabel: '$sectionId/$groupId'));
  }

  Map<String, GlobalKey> _paneKeys(
    String sectionId,
    List<SettingsGroupSpec> groups,
  ) {
    return <String, GlobalKey>{
      for (final group in groups) group.id: _groupKey(sectionId, group.id),
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = (screen.width * _kDialogWidthFraction).clamp(
      _kDialogMinWidth,
      _kDialogMaxWidth,
    );
    final dialogHeight = (screen.height * _kDialogHeightFraction).clamp(
      _kDialogMinHeight,
      _kDialogMaxHeight,
    );

    const applicationGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'storage', title: 'Storage'),
      SettingsGroupSpec(id: 'safety', title: 'Safety'),
      SettingsGroupSpec(id: 'updates', title: 'Updates'),
      SettingsGroupSpec(id: 'support', title: 'Support'),
    ];
    const agentsGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'cliSkill', title: 'CLI And Skills'),
      SettingsGroupSpec(id: 'hooks', title: 'Status Hooks'),
      SettingsGroupSpec(id: 'behavior', title: 'Behavior'),
    ];
    const aiTextGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'generation', title: 'Generation'),
      SettingsGroupSpec(id: 'instructions', title: 'Instructions'),
    ];
    const terminalGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'typography', title: 'Typography'),
      SettingsGroupSpec(id: 'cursor', title: 'Cursor'),
      SettingsGroupSpec(id: 'appearance', title: 'Appearance'),
      SettingsGroupSpec(id: 'interaction', title: 'Interaction'),
      SettingsGroupSpec(id: 'advanced', title: 'Advanced'),
    ];

    final sections = <SettingsSectionData>[
      SettingsSectionData(
        id: 'application',
        title: 'Application',
        description: 'Storage, safety, updates and support.',
        icon: AleraIcons.tune,
        entries: applicationSearchEntries,
        groups: applicationGroups,
        builder: (_) => ApplicationSettingsPane(
          general: settings.general,
          groupKeys: _paneKeys('application', applicationGroups),
        ),
      ),
      SettingsSectionData(
        id: 'agents',
        title: 'Agents',
        description: 'Agent Hooks, Notifications And Alera Skills.',
        icon: AleraIcons.agent,
        entries: agentsSearchEntries,
        groups: agentsGroups,
        builder: (_) => AgentsSettingsPane(
          agents: settings.agents,
          groupKeys: _paneKeys('agents', agentsGroups),
        ),
      ),
      SettingsSectionData(
        id: 'aiText',
        title: 'AI Text',
        description: 'AI-generated source control text.',
        icon: AleraIcons.ai,
        entries: aiTextSearchEntries,
        groups: aiTextGroups,
        onReset: controller.resetAiTextGenerationSettings,
        builder: (_) => AiTextSettingsPane(
          settings: settings.aiTextGeneration,
          groupKeys: _paneKeys('aiText', aiTextGroups),
          onChanged: (aiText) => controller.updateAiTextGeneration(aiText),
        ),
      ),
      SettingsSectionData(
        id: 'editor',
        title: 'Editor',
        description: 'Code editor defaults.',
        icon: AleraIcons.code,
        entries: editorSearchEntries,
        onReset: controller.resetEditorSettings,
        builder: (_) => EditorSettingsPane(
          settings: settings.editor,
          onChanged: (editor) => controller.updateEditor(editor),
        ),
      ),
      SettingsSectionData(
        id: 'terminal',
        title: 'Terminal',
        description: 'Appearance defaults for new terminal sessions.',
        icon: AleraIcons.terminal,
        entries: terminalSearchEntries,
        groups: terminalGroups,
        onReset: controller.resetTerminalSettings,
        builder: (_) => TerminalSettingsPane(
          settings: settings.terminal,
          fontSuggestions: _fontSuggestions,
          groupKeys: _paneKeys('terminal', terminalGroups),
          onChanged: (terminal) => controller.updateTerminal(terminal),
        ),
      ),
      SettingsSectionData(
        id: 'keyboard',
        title: 'Keyboard',
        description: 'Shortcuts and key bindings.',
        icon: AleraIcons.keyboard,
        entries: keyboardSearchEntries,
        onReset: controller.resetKeyboardShortcuts,
        builder: (_) => const KeyboardSettingsPane(),
      ),
      SettingsSectionData(
        id: 'projects',
        title: 'Projects',
        description: 'Per-Project Workspace Setup.',
        icon: AleraIcons.folderSpecial,
        entries: projectSearchEntries,
        navGroup: SettingsNavGroup.resources,
        builder: (_) => const ProjectSettingsPane(),
      ),
      SettingsSectionData(
        id: 'remoteHosts',
        title: 'Remote Hosts',
        description: 'SSH runtime targets.',
        icon: AleraIcons.host,
        entries: remoteHostSearchEntries,
        navGroup: SettingsNavGroup.resources,
        builder: (_) => const RemoteHostSettingsPane(),
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
      maxWidth: dialogWidth,
      maxHeight: dialogHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsSidebar(
            queryController: _searchController,
            query: _query,
            visibleSections: visibleSections,
            activeSectionId: activeSection?.id,
            onSelect: (id) => setState(() => _activeSectionId = id),
          ),
          const VerticalDivider(width: 1, color: AleraTokens.borderSubtle),
          Expanded(
            child: activeSection != null
                ? SettingsContent(
                    section: activeSection,
                    groupKeys: _keysFor(activeSection.id),
                    scrollToGroupId: activeSection.firstMatchingGroupId(_query),
                    onClose: () => Navigator.of(context).pop(),
                  )
                : NoSettingsResults(onClose: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }
}

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
