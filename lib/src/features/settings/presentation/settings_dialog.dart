import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_settings_pane.dart';
import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_text_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/editor_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/general_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/projects_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_hosts_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/terminal_pane.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog_content.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog_sidebar.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _kDialogMaxWidth = 920;
const double _kDialogMaxHeight = 680;

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

    final sections = <SettingsSectionData>[
      SettingsSectionData(
        id: 'general',
        title: 'General',
        description: 'Storage and integrations.',
        icon: AleraIcons.tune,
        entries: generalSearchEntries,
        builder: (_) => GeneralSettingsPane(
          general: settings.general,
          agents: settings.agents,
        ),
      ),
      SettingsSectionData(
        id: 'projects',
        title: 'Projects',
        description: 'Per-Project Workspace Setup.',
        icon: AleraIcons.folderSpecial,
        entries: projectSearchEntries,
        builder: (_) => const ProjectSettingsPane(),
      ),
      SettingsSectionData(
        id: 'remoteHosts',
        title: 'Remote Hosts',
        description: 'SSH runtime targets.',
        icon: AleraIcons.host,
        entries: remoteHostSearchEntries,
        builder: (_) => const RemoteHostSettingsPane(),
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
        id: 'aiText',
        title: 'AI Text',
        description: 'AI-generated source control text.',
        icon: AleraIcons.ai,
        entries: aiTextSearchEntries,
        onReset: controller.resetAiTextGenerationSettings,
        builder: (_) => AiTextSettingsPane(
          settings: settings.aiTextGeneration,
          onChanged: (aiText) => controller.updateAiTextGeneration(aiText),
        ),
      ),
      SettingsSectionData(
        id: 'terminal',
        title: 'Terminal',
        description: 'Appearance defaults for new terminal sessions.',
        icon: AleraIcons.terminal,
        entries: terminalSearchEntries,
        onReset: controller.resetTerminalSettings,
        builder: (_) => TerminalSettingsPane(
          settings: settings.terminal,
          fontSuggestions: _fontSuggestions,
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
          SettingsSidebar(
            queryController: _searchController,
            visibleSections: visibleSections,
            activeSectionId: activeSection?.id,
            onSelect: (id) => setState(() => _activeSectionId = id),
          ),
          const VerticalDivider(width: 1, color: AleraTokens.borderSubtle),
          Expanded(
            child: activeSection != null
                ? SettingsContent(
                    section: activeSection,
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
