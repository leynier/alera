import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/automations/presentation/automations_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_entry_points.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_hosts_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_panels_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/explorer_panel.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_panel.dart';
import 'package:alera_mobile/src/features/workbench/presentation/source_control_panel.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_viewer_screen.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_host_marker.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_text_search_panel.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/agent_presence_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_tab_session.dart';
import 'package:alera_mobile/src/features/terminal/presentation/agent_profile_launch_sheet.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_keys_settings_screen.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_run_state_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

part 'workspace_tab_strip.dart';
part 'workspace_tabs_actions.dart';
part 'workspace_tabs_close.dart';
part 'workspace_tabs_panel_body.dart';
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
      case _NewAgentProfileTabAction(:final profile):
        await _launchProfileTab(profile);
    }
  }

  Future<List<AgentProfileSummary>> _newTabMenuProfiles() {
    return ref
        .read(
          tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
        )
        .listNewTabMenuProfiles();
  }

  Future<void> _launchProfileTab(AgentProfileSummary profile) async {
    if (_creating || !profile.showInNewTabMenu) {
      return;
    }
    await showAgentProfileLaunchSheet(
      context,
      profile: profile,
      hostId: widget.hostId,
      workspaceId: widget.workspace.id,
      onLaunch: ({required prompt}) async {
        final tabId = await ref
            .read(
              tabsControllerProvider(
                widget.hostId,
                widget.workspace.id,
              ).notifier,
            )
            .launchAgentProfileTab(profile.id, prompt: prompt);
        if (mounted) {
          setState(() {
            _selectedTabId = tabId;
          });
        }
      },
    );
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
      ref.listen(
        terminalSessionControllerProvider(
          widget.hostId,
          tab.id,
          observe: _observes(tab),
        ),
        (previous, next) {
          if (next case AsyncError(:final error)
              when error is DesktopReclaimedTerminal) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Desktop took back the terminal')),
            );
            Navigator.of(context).pop();
          }
        },
      );
    }
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        // This screen stacks a title row and a tab strip. The default 56dp
        // toolbar leaves ~18dp of dead space under the title before the chips
        // start; 48dp still fits the back button exactly.
        toolbarHeight: AleraTokens.minTapTarget,
        title: _WorkspaceTabsTitle(
          title: WorkspaceHostTitle(
            name: widget.workspace.name,
            host: ref
                .watch(workspaceHostsControllerProvider(widget.hostId))
                .value
                ?.hostOf(widget.workspace),
          ),
          panel: panel,
        ),
        actions: <Widget>[
          if (!showTerminalChrome)
            IconButton(
              tooltip: 'Show Terminal',
              onPressed: () => _selectPanel(WorkspacePanelDestination.terminal),
              icon: const Icon(AleraIcons.terminal),
            ),
          _moreActionsMenu(panelCapabilities, panel),
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

  void _openTab(String tabId) {
    if (!mounted) {
      return;
    }
    setState(() => _selectedTabId = tabId);
    _selectPanel(WorkspacePanelDestination.terminal);
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
          observe: _observes(tab),
          automationRunId: _automationRunId(tab),
        ),
        null => _EmptyTabs(
          creating: _creating,
          onNewTab: () =>
              unawaited(_createTabOfKind(const _NewTerminalTabAction())),
          targetUnavailable: tabList.isNotEmpty && !widget.selectFallbackTab,
        ),
      },
      AsyncError(:final error) => AleraEmptyState(
        icon: AleraIcons.loadFailed,
        title: 'Could not load tabs',
        message: 'Check the connection to the host and try again.',
        detail: error.toString(),
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(
            tabsControllerProvider(widget.hostId, widget.workspace.id),
          ),
          icon: const Icon(AleraIcons.refresh),
          label: const Text('Retry'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}
