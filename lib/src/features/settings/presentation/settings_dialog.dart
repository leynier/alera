import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/account/presentation/account_settings_pane.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_settings_pane.dart';
import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/features/settings/presentation/account_settings_search_entries.dart';
import 'package:alera/src/features/settings/presentation/ai_dictation_search_entries.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profiles_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/agents_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_quota_settings_group.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_text_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_dictation_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/application_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/browser_settings_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/editor_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/mobile_devices_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/projects_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_hosts_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/terminal_pane.dart';
import 'package:alera/src/features/text_actions/presentation/text_actions_settings_pane.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog_content.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog_sidebar.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries_quota.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries_terminal.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries_resources.dart';
import 'package:alera/src/features/settings/presentation/text_actions_search_entries.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
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
  const SettingsDialog({
    super.key,
    this.initialSectionId = 'application',
    this.initialProjectId,
  });

  final String initialSectionId;
  final String? initialProjectId;

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
    _activeSectionId = widget.initialSectionId;
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

  Future<void> _reloadShellEnvironment() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(runtimeHostClientProvider)
          .runtimeRequest('shellEnvironment.reload');
      final count = result is Map && result['pathEntryCount'] is num
          ? (result['pathEntryCount'] as num).toInt()
          : 0;
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? 'Shell environment reloaded ($count PATH entries)'
                : 'Shell environment reloaded',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reload shell environment')),
      );
    }
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
      SettingsGroupSpec(id: 'runtime', title: 'Runtime'),
      SettingsGroupSpec(id: 'diagnostics', title: 'Diagnostics'),
      SettingsGroupSpec(id: 'updates', title: 'Updates'),
      SettingsGroupSpec(id: 'support', title: 'Support'),
    ];
    const accountGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'identity', title: 'Identity'),
      SettingsGroupSpec(id: 'push', title: 'Mobile Push'),
      SettingsGroupSpec(id: 'ownership', title: 'Ownership'),
    ];
    const agentsGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'cliSkill', title: 'CLI And Skills'),
      SettingsGroupSpec(id: 'hooks', title: 'Status Hooks'),
      SettingsGroupSpec(id: 'behavior', title: 'Behavior'),
    ];
    const quotaGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'providers', title: 'Providers'),
      SettingsGroupSpec(id: 'claude', title: 'Claude'),
      SettingsGroupSpec(id: 'credentials', title: 'Credentials'),
    ];
    const textActionsGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'actions', title: 'Actions'),
    ];
    const aiTextGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'generation', title: 'Generation'),
      SettingsGroupSpec(id: 'commitMessage', title: 'Commit Messages'),
      SettingsGroupSpec(
        id: 'pullRequestDetails',
        title: 'Pull Request Details',
      ),
      SettingsGroupSpec(id: 'readingDiff', title: 'Reading Diffs'),
      SettingsGroupSpec(id: 'workspaceIdentity', title: 'Workspace Identity'),
    ];
    const aiDictationGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'transcription', title: 'Transcription'),
      SettingsGroupSpec(id: 'remote', title: 'Remote Transcription'),
      SettingsGroupSpec(id: 'models', title: 'Local Whisper Models'),
      SettingsGroupSpec(id: 'processing', title: 'Speech Processing'),
      SettingsGroupSpec(id: 'test', title: 'Test AI Dictation'),
    ];
    const terminalGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'typography', title: 'Typography'),
      SettingsGroupSpec(id: 'cursor', title: 'Cursor'),
      SettingsGroupSpec(id: 'appearance', title: 'Appearance'),
      SettingsGroupSpec(id: 'interaction', title: 'Interaction'),
      SettingsGroupSpec(id: 'advanced', title: 'Advanced'),
    ];
    const browserGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'general', title: 'General'),
      SettingsGroupSpec(id: 'profiles', title: 'Profiles'),
      SettingsGroupSpec(id: 'certificates', title: 'Trusted Certificates'),
      SettingsGroupSpec(id: 'data', title: 'Browsing Data'),
    ];
    const mobileDeviceGroups = <SettingsGroupSpec>[
      SettingsGroupSpec(id: 'gateway', title: 'Mobile Gateway'),
      SettingsGroupSpec(id: 'pairing', title: 'Link A Device'),
      SettingsGroupSpec(id: 'offers', title: 'Active Pairing Offers'),
      SettingsGroupSpec(id: 'devices', title: 'Paired Devices'),
    ];

    final sections = <SettingsSectionData>[
      SettingsSectionData(
        id: 'account',
        title: 'Account',
        description: 'Identity, mobile push and runtime ownership.',
        icon: AleraIcons.account,
        entries: accountSearchEntries,
        groups: accountGroups,
        builder: (_) =>
            AccountSettingsPane(groupKeys: _paneKeys('account', accountGroups)),
      ),
      SettingsSectionData(
        id: 'application',
        title: 'Application',
        description: 'Storage, safety, runtime, diagnostics and updates.',
        icon: AleraIcons.tune,
        entries: applicationSearchEntries,
        groups: applicationGroups,
        builder: (_) => ApplicationSettingsPane(
          general: settings.general,
          terminal: settings.terminal,
          diagnostics: settings.diagnostics,
          groupKeys: _paneKeys('application', applicationGroups),
        ),
      ),
      SettingsSectionData(
        id: 'agents',
        title: 'Agents',
        description: 'Agent hooks, notifications and Alera skills.',
        icon: AleraIcons.agent,
        entries: agentsSearchEntries,
        groups: agentsGroups,
        builder: (_) => AgentsSettingsPane(
          agents: settings.agents,
          groupKeys: _paneKeys('agents', agentsGroups),
        ),
      ),
      SettingsSectionData(
        id: 'quotas',
        title: 'Quotas',
        description:
            'Provider usage, Claude profiles and credential environment.',
        icon: AleraIcons.quota,
        entries: quotaSearchEntries,
        groups: quotaGroups,
        builder: (_) => AgentQuotaSettingsPane(
          settings: settings.agents.quotas,
          groupKeys: _paneKeys('quotas', quotaGroups),
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
        id: 'aiDictation',
        title: 'AI Dictation',
        description:
            'Local, Codex subscription, and OpenAI-compatible speech-to-text.',
        icon: AleraIcons.mic,
        entries: aiDictationSearchEntries,
        groups: aiDictationGroups,
        onReset: controller.resetAiDictation,
        builder: (_) => AiDictationSettingsPane(
          settings: settings.aiDictation,
          groupKeys: _paneKeys('aiDictation', aiDictationGroups),
          onChanged: controller.updateAiDictation,
        ),
      ),
      SettingsSectionData(
        id: 'textActions',
        title: 'Text Actions',
        description: 'Create reusable replacements for selected text.',
        icon: AleraIcons.text,
        entries: textActionsSearchEntries,
        groups: textActionsGroups,
        navGroup: SettingsNavGroup.resources,
        builder: (_) => TextActionsSettingsPane(
          settings: settings.textActions,
          aiTextSettings: settings.aiTextGeneration,
          groupKeys: _paneKeys('textActions', textActionsGroups),
          onChanged: controller.updateTextActions,
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
          onReloadShellEnvironment: _reloadShellEnvironment,
        ),
      ),
      SettingsSectionData(
        id: 'browser',
        title: 'Browser',
        description: 'System engine, profiles and browsing data.',
        icon: AleraIcons.public,
        entries: browserSearchEntries,
        groups: browserGroups,
        builder: (_) =>
            BrowserSettingsPane(groupKeys: _paneKeys('browser', browserGroups)),
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
        description: 'Per-project workspace setup.',
        icon: AleraIcons.folderSpecial,
        entries: projectSearchEntries,
        navGroup: SettingsNavGroup.resources,
        builder: (_) =>
            ProjectSettingsPane(initialProjectId: widget.initialProjectId),
      ),
      SettingsSectionData(
        id: 'mobileDevices',
        title: 'Mobile Devices',
        description: 'Pair and manage the mobile companion app.',
        icon: AleraIcons.mobileDevice,
        entries: mobileDeviceSearchEntries,
        groups: mobileDeviceGroups,
        navGroup: SettingsNavGroup.resources,
        builder: (_) => MobileDevicesSettingsPane(
          groupKeys: _paneKeys('mobileDevices', mobileDeviceGroups),
        ),
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
      SettingsSectionData(
        id: 'agentProfiles',
        title: 'Agent Profiles',
        description: 'Launch configurations orchestration can dispatch to.',
        icon: AleraIcons.agent,
        entries: agentProfileSearchEntries,
        navGroup: SettingsNavGroup.resources,
        builder: (_) => const AgentProfilesSettingsPane(),
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
