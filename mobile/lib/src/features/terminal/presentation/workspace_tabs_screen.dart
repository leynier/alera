import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_panels_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/explorer_panel.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_panel.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_panel.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_viewer_screen.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_text_search_panel.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/agent_presence_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_tab_session.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_keys_settings_screen.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_run_state_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

part 'workspace_tab_strip.dart';
part 'workspace_tabs_close.dart';
part 'workspace_tabs_panel_menu.dart';

/// Tabs of one workspace: a horizontally scrollable chip switcher with one
/// tab visible at a time. Splits stay a desktop concept.
class const WorkspaceTabsScreen({
  super.key,
  required final String hostId,
  required final WorkspaceSummary workspace,
  final String? initialTabId,
  final bool selectFallbackTab = true,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<WorkspaceTabsScreen> createState() =>
      _WorkspaceTabsScreenState();
}

class _WorkspaceTabsScreenState extends ConsumerState<WorkspaceTabsScreen> {
  static final Logger _logger = Logger('WorkspaceTabsScreen');
  String? _selectedTabId;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _selectedTabId = widget.initialTabId;
  }

  Future<void> _createTabOfKind(_NewTabAction action) async {
    switch (action) {
      case _NewTerminalTabAction():
        await _createTab();
      case _NewAgentProfileTabAction(:final profileId):
        await _launchProfileTab(profileId);
    }
  }

  Future<List<AgentProfileSummary>> _newTabMenuProfiles() {
    return ref
        .read(
          tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
        )
        .listNewTabMenuProfiles();
  }

  Future<void> _launchProfileTab(String profileId) async {
    if (_creating) {
      return;
    }
    setState(() {
      _creating = true;
    });
    try {
      final tabId = await ref
          .read(
            tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
          )
          .launchAgentProfileTab(profileId);
      if (mounted) {
        setState(() {
          _selectedTabId = tabId;
        });
      }
    } on Object catch (error, stackTrace) {
      _logger.warning('could not launch agent profile tab', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  Future<void> _createTab() async {
    if (_creating) {
      return;
    }
    setState(() {
      _creating = true;
    });
    try {
      final tabId = await ref
          .read(
            tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
          )
          .createTerminalTab();
      if (mounted) {
        setState(() {
          _selectedTabId = tabId;
        });
      }
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not create terminal tab.', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not create tab: $error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  Future<void> _renameTab(WorkspaceTabSummary tab) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => AleraRenameDialog(
        title: 'Rename Tab',
        labelText: 'Tab Title',
        initialValue: tab.displayTitle,
      ),
    );
    if (title == null || !mounted) return;
    try {
      await ref
          .read(
            tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
          )
          .renameTab(tab, title);
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not rename workspace tab.', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not rename tab: $error')));
      }
    }
  }

  Future<void> _showTabActions(
    WorkspaceTabSummary tab, {
    required bool canRename,
    required bool canGenerateTitle,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            if (canRename)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename Tab'),
                onTap: () => Navigator.of(context).pop('rename'),
              ),
            if (canGenerateTitle && tab.isTerminal)
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(
                  tab.payload['agentTitleStatus'] == 'generating'
                      ? 'Generating title...'
                      : tab.payload['agentTitleSource'] == 'generated'
                      ? 'Regenerate Title'
                      : 'Generate Title',
                ),
                enabled: tab.payload['agentTitleStatus'] != 'generating',
                onTap: () => Navigator.of(context).pop('generateTitle'),
              ),
            if (tab.isTerminal)
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Close Tab'),
                onTap: () => Navigator.of(context).pop('close'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'generateTitle') {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref
            .read(
              tabsControllerProvider(
                widget.hostId,
                widget.workspace.id,
              ).notifier,
            )
            .generateTitle(tab);
      } on Object catch (error, stackTrace) {
        _logger.warning('Could not generate agent title.', error, stackTrace);
        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Could not generate title: $error')),
          );
        }
      }
    }
    if (action == 'rename') await _renameTab(tab);
    if (action == 'close') await _closeTab(tab);
  }

  /// A desktop Markdown viewer tab opens its preview on top of the terminal
  /// rather than replacing it, so the selected terminal stays attached.
  void _openMarkdownTab(WorkspaceTabSummary tab) {
    final filePath = tab.filePath;
    if (filePath == null) {
      return;
    }
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkspaceFileViewerScreen(
            hostId: widget.hostId,
            workspaceId: tab.workspaceId,
            relativePath: filePath,
          ),
        ),
      ),
    );
  }

  WorkspaceTabSummary? _selectedTab(List<WorkspaceTabSummary> tabs) {
    final supported = tabs.where((tab) => tab.isTerminal).toList();
    if (supported.isEmpty) {
      return null;
    }
    for (final tab in supported) {
      if (tab.id == _selectedTabId) {
        return tab;
      }
    }
    if (!widget.selectFallbackTab) {
      return null;
    }
    return supported.first;
  }

  /// Agent state per tab, so a chip can say whether its agent is working or
  /// waiting without opening it. Absent while presence is still loading, which
  /// leaves the chip exactly as it was before.
  Map<String, AgentPresenceSummary> _presenceByTabId() {
    final presence = ref
        .watch(agentPresenceControllerProvider(widget.hostId))
        .value;
    if (presence == null) {
      return const <String, AgentPresenceSummary>{};
    }
    return <String, AgentPresenceSummary>{
      for (final summary in presence)
        if (summary.workspaceId == widget.workspace.id) summary.tabId: summary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tabsProvider = tabsControllerProvider(
      widget.hostId,
      widget.workspace.id,
    );
    final tabs = ref.watch(tabsProvider);
    final selectedTab = tabs.value == null ? null : _selectedTab(tabs.value!);
    final workspaceClient = ref
        .watch(workspaceClientProvider(widget.hostId))
        .value;
    final canGenerateTitle =
        workspaceClient is MobileAgentTitleClient &&
        (workspaceClient as MobileAgentTitleClient).supportsAgentTitles;
    final canOpenMarkdownTabs =
        workspaceClient is MobileCodexWorkspaceClient &&
        (workspaceClient as MobileCodexWorkspaceClient)
            .supportsCodexWorkspaceFiles;
    final canRename =
        ref
            .watch(workspaceClientProvider(widget.hostId))
            .value
            ?.supportsTabRename ==
        true;
    final panelCapabilities =
        ref
            .watch(workspacePanelCapabilitiesControllerProvider(widget.hostId))
            .value ??
        const WorkspacePanelCapabilities();
    final destinations = panelCapabilities.destinations;
    final selectedPanel = ref.watch(
      selectedWorkspacePanelControllerProvider(
        widget.hostId,
        widget.workspace.id,
      ),
    );
    final panel = destinations.contains(selectedPanel)
        ? selectedPanel
        : WorkspacePanelDestination.terminal;
    final showTerminalChrome = panel == WorkspacePanelDestination.terminal;
    if (selectedTab case final WorkspaceTabSummary tab when tab.isTerminal) {
      // The desktop taking the viewport back sends this phone to the
      // workspace list; re-entering the tab simply claims again.
      ref.listen(terminalSessionControllerProvider(widget.hostId, tab.id), (
        previous,
        next,
      ) {
        if (next case AsyncError(:final error)
            when error is DesktopReclaimedTerminal) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Desktop took back the terminal')),
          );
          Navigator.of(context).pop();
        }
      });
    }
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        // This screen stacks a title row and a tab strip. The default 56dp
        // toolbar leaves ~18dp of dead space under the title before the chips
        // start; 48dp still fits the back button exactly.
        toolbarHeight: AleraTokens.minTapTarget,
        title: Text(widget.workspace.name, overflow: .ellipsis),
        actions: <Widget>[
          PopupMenuButton<_TabsMenuAction>(
            tooltip: 'More Actions',
            onSelected: (action) {
              switch (action) {
                case _QuickKeysMenuAction():
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TerminalKeysSettingsScreen(),
                    ),
                  );
                case _SelectPanelAction(:final destination):
                  ref
                      .read(
                        selectedWorkspacePanelControllerProvider(
                          widget.hostId,
                          widget.workspace.id,
                        ).notifier,
                      )
                      .select(destination);
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<_TabsMenuAction>>[
              if (panelCapabilities
                  .hasAny) ...<PopupMenuEntry<_TabsMenuAction>>[
                for (final destination in destinations)
                  PopupMenuItem<_TabsMenuAction>(
                    value: _SelectPanelAction(destination),
                    height: AleraTokens.minTapTarget,
                    child: _PanelMenuRow(
                      icon: _panelIcon(destination),
                      label: _panelLabel(destination),
                      selected: destination == panel,
                    ),
                  ),
                const PopupMenuDivider(),
              ],
              const PopupMenuItem<_TabsMenuAction>(
                value: _QuickKeysMenuAction(),
                height: AleraTokens.minTapTarget,
                child: Text('Terminal Quick Keys'),
              ),
            ],
          ),
        ],
        bottom: showTerminalChrome && tabs.value?.isNotEmpty == true
            ? PreferredSize(
                preferredSize: const .fromHeight(AleraTokens.tabStripHeight),
                child: _TabStrip(
                  tabs: tabs.value!,
                  selectedTabId: _selectedTab(tabs.value!)?.id,
                  creating: _creating,
                  presenceByTabId: _presenceByTabId(),
                  canOpenMarkdownTabs: canOpenMarkdownTabs,
                  onSelect: (tab) {
                    if (tab.isMarkdownViewer) {
                      _openMarkdownTab(tab);
                      return;
                    }
                    setState(() {
                      _selectedTabId = tab.id;
                    });
                  },
                  onClose: _closeTab,
                  onActions: (tab) => _showTabActions(
                    tab,
                    canRename: canRename,
                    canGenerateTitle: canGenerateTitle,
                  ),
                  onNewTab: (action) => unawaited(_createTabOfKind(action)),
                  loadNewTabProfiles: _newTabMenuProfiles,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: showTerminalChrome ? _terminalBody(tabs) : _panelBody(panel),
      ),
    );
  }

  Widget _terminalBody(AsyncValue<List<WorkspaceTabSummary>> tabs) {
    // The last known tab list wins over a reload: reconnecting to the host
    // rebuilds this provider, and swapping the body for a spinner disposes
    // the tab's state along with anything it is waiting on, which silently
    // dropped an attachment whose upload was still in flight.
    return switch (tabs) {
      AsyncValue(value: final tabList?) => switch (_selectedTab(tabList)) {
        final WorkspaceTabSummary tab => TerminalTabView(
          key: ValueKey<String>(tab.id),
          hostId: widget.hostId,
          workspaceId: tab.workspaceId,
          tabId: tab.id,
        ),
        null => _EmptyTabs(
          creating: _creating,
          onNewTab: () =>
              unawaited(_createTabOfKind(const _NewTerminalTabAction())),
          targetUnavailable: tabList.isNotEmpty && !widget.selectFallbackTab,
        ),
      },
      AsyncError(:final error) => Center(
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Text(error.toString(), textAlign: .center),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _panelBody(WorkspacePanelDestination panel) {
    final hostId = widget.hostId;
    final workspaceId = widget.workspace.id;
    return switch (panel) {
      WorkspacePanelDestination.explorer => ExplorerPanel(
        hostId: hostId,
        workspaceId: workspaceId,
      ),
      WorkspacePanelDestination.search => WorkspaceTextSearchPanel(
        hostId: hostId,
        workspaceId: workspaceId,
      ),
      WorkspacePanelDestination.sourceControl => SourceControlPanel(
        hostId: hostId,
        workspaceId: workspaceId,
      ),
      WorkspacePanelDestination.pullRequest => PullRequestPanel(
        hostId: hostId,
        workspaceId: workspaceId,
      ),
      WorkspacePanelDestination.terminal => _terminalBody(
        ref.watch(tabsControllerProvider(widget.hostId, widget.workspace.id)),
      ),
    };
  }
}
