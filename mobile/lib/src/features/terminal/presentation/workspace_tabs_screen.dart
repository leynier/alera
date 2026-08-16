import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/codex_chat/presentation/mobile_codex_chat_screen.dart';
import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_composer_draft_store.dart';
import 'package:alera_mobile/src/features/terminal/application/agent_presence_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_tab_session.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_keys_settings_screen.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_run_state_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

part 'workspace_tab_strip.dart';

/// Tabs of one workspace: a horizontally scrollable chip switcher with one
/// tab visible at a time. Splits stay a desktop concept.
class WorkspaceTabsScreen extends ConsumerStatefulWidget {
  const WorkspaceTabsScreen({
    super.key,
    required this.hostId,
    required this.workspace,
    this.initialTabId,
    this.selectFallbackTab = true,
  });

  final String hostId;
  final WorkspaceSummary workspace;
  final String? initialTabId;
  final bool selectFallbackTab;

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
      case _NewTabAction.terminal:
        await _createTab();
      case _NewTabAction.codex:
        await _createCodexTab();
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

  Future<void> _createCodexTab() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final tabId = await ref
          .read(
            tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
          )
          .createCodexTab();
      if (mounted) setState(() => _selectedTabId = tabId);
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not create Codex tab.', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create Codex tab: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _focusBoundCodexTab(String workspaceId, String tabId) async {
    if (workspaceId == widget.workspace.id) {
      if (mounted) setState(() => _selectedTabId = tabId);
      return;
    }
    try {
      final client = await ref.read(
        workspaceClientProvider(widget.hostId).future,
      );
      final workspaces = await client.listWorkspaces();
      WorkspaceSummary? workspace;
      for (final candidate in workspaces) {
        if (candidate.id == workspaceId) {
          workspace = candidate;
          break;
        }
      }
      if (workspace == null) {
        throw StateError('The workspace for this Codex chat is unavailable.');
      }
      final targetWorkspace = workspace;
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkspaceTabsScreen(
            hostId: widget.hostId,
            workspace: targetWorkspace,
            initialTabId: tabId,
            selectFallbackTab: false,
          ),
        ),
      );
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not focus bound Codex tab.', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the Codex chat: $error')),
        );
      }
    }
  }

  Future<void> _closeTab(WorkspaceTabSummary tab) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Tab'),
        content: Text(tab.displayTitle),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final tabsController = ref.read(
      tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
    );
    final draftStore = ref.read(mobileCodexComposerDraftStoreProvider);
    try {
      final closed = await tabsController.closeTab(tab);
      if (!closed) return;
      draftStore.remove(widget.hostId, tab.id);
      if (mounted && _selectedTabId == tab.id) {
        setState(() {
          _selectedTabId = null;
        });
      }
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not close workspace tab.', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not close tab: $error')));
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
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (canRename)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename Tab'),
                onTap: () => Navigator.of(context).pop('rename'),
              ),
            if (tab.isTerminal || tab.isCodex)
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
    if (action == 'rename') await _renameTab(tab);
    if (action == 'close') await _closeTab(tab);
  }

  WorkspaceTabSummary? _selectedTab(List<WorkspaceTabSummary> tabs) {
    final supported = tabs
        .where((tab) => tab.isTerminal || tab.isCodex)
        .toList();
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
    ref.listen(tabsProvider, (previous, next) {
      final previousTabs = previous?.value;
      final currentTabs = next.value;
      if (previousTabs == null || currentTabs == null) return;
      final currentTabIds = <String>{for (final tab in currentTabs) tab.id};
      final drafts = ref.read(mobileCodexComposerDraftStoreProvider);
      for (final tab in previousTabs) {
        if (tab.isCodex && !currentTabIds.contains(tab.id)) {
          drafts.remove(widget.hostId, tab.id);
        }
      }
    });
    final tabs = ref.watch(tabsProvider);
    final selectedTab = tabs.value == null ? null : _selectedTab(tabs.value!);
    final canRename =
        ref
            .watch(workspaceClientProvider(widget.hostId))
            .value
            ?.supportsTabRename ==
        true;
    if (selectedTab case final WorkspaceTabSummary tab when tab.isTerminal) {
      // The desktop taking the viewport back sends this phone to the
      // workspace list; re-entering the tab simply claims again.
      ref.listen(terminalSessionControllerProvider(widget.hostId, tab.id), (
        previous,
        next,
      ) {
        if (next case AsyncError(
          :final error,
        ) when error is DesktopReclaimedTerminal) {
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
        title: Text(widget.workspace.name, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          PopupMenuButton<_TabsMenuAction>(
            tooltip: 'More Actions',
            onSelected: (action) {
              switch (action) {
                case _TabsMenuAction.quickKeys:
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TerminalKeysSettingsScreen(),
                    ),
                  );
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<_TabsMenuAction>>[
              const PopupMenuItem<_TabsMenuAction>(
                value: _TabsMenuAction.quickKeys,
                child: Text('Terminal Quick Keys'),
              ),
            ],
          ),
        ],
        bottom: tabs.value?.isNotEmpty == true
            ? PreferredSize(
                preferredSize: const Size.fromHeight(
                  AleraTokens.tabStripHeight,
                ),
                child: _TabStrip(
                  tabs: tabs.value!,
                  selectedTabId: _selectedTab(tabs.value!)?.id,
                  creating: _creating,
                  presenceByTabId: _presenceByTabId(),
                  onSelect: (tab) {
                    setState(() {
                      _selectedTabId = tab.id;
                    });
                  },
                  onClose: _closeTab,
                  onActions: (tab) => _showTabActions(
                    tab,
                    canRename: canRename && !tab.isCodex,
                  ),
                  onNewTab: (action) => unawaited(_createTabOfKind(action)),
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: switch (tabs) {
          AsyncData(value: final tabList) => switch (_selectedTab(tabList)) {
            final WorkspaceTabSummary tab when tab.isCodex =>
              MobileCodexChatScreen(
                key: ValueKey<String>(tab.id),
                hostId: widget.hostId,
                tabId: tab.id,
                workspaceId: tab.workspaceId,
                onFocusBoundTab: (workspaceId, tabId) =>
                    unawaited(_focusBoundCodexTab(workspaceId, tabId)),
              ),
            final WorkspaceTabSummary tab => TerminalTabView(
              key: ValueKey<String>(tab.id),
              hostId: widget.hostId,
              workspaceId: tab.workspaceId,
              tabId: tab.id,
            ),
            null => _EmptyTabs(
              creating: _creating,
              onNewTab: () =>
                  unawaited(_createTabOfKind(_NewTabAction.terminal)),
              targetUnavailable:
                  tabList.isNotEmpty && !widget.selectFallbackTab,
            ),
          },
          AsyncError(:final error) => Center(
            child: Padding(
              padding: AleraTokens.contentPadding,
              child: Text(error.toString(), textAlign: TextAlign.center),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

enum _NewTabAction { terminal, codex }

enum _TabsMenuAction { quickKeys }
