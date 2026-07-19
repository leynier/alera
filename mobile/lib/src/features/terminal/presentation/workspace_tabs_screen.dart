import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tabs of one workspace: a horizontally scrollable chip switcher with one
/// tab visible at a time. Splits stay a desktop concept.
class WorkspaceTabsScreen extends ConsumerStatefulWidget {
  const WorkspaceTabsScreen({
    super.key,
    required this.hostId,
    required this.workspace,
  });

  final String hostId;
  final WorkspaceSummary workspace;

  @override
  ConsumerState<WorkspaceTabsScreen> createState() =>
      _WorkspaceTabsScreenState();
}

class _WorkspaceTabsScreenState extends ConsumerState<WorkspaceTabsScreen> {
  String? _selectedTabId;
  bool _creating = false;

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
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could Not Create Tab: $error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  Future<void> _closeTab(WorkspaceTabSummary tab) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Tab'),
        content: Text(tab.title),
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
    try {
      await ref
          .read(
            tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
          )
          .closeTab(tab);
      if (mounted && _selectedTabId == tab.id) {
        setState(() {
          _selectedTabId = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could Not Close Tab: $error')));
      }
    }
  }

  WorkspaceTabSummary? _selectedTab(List<WorkspaceTabSummary> tabs) {
    final terminals = tabs.where((tab) => tab.isTerminal).toList();
    if (terminals.isEmpty) {
      return null;
    }
    for (final tab in terminals) {
      if (tab.id == _selectedTabId) {
        return tab;
      }
    }
    return terminals.first;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(
      tabsControllerProvider(widget.hostId, widget.workspace.id),
    );
    final selectedTab = tabs.value == null ? null : _selectedTab(tabs.value!);
    if (selectedTab != null) {
      // The desktop taking the viewport back sends this phone to the
      // workspace list; re-entering the tab simply claims again.
      ref.listen(
        terminalSessionControllerProvider(widget.hostId, selectedTab.id),
        (previous, next) {
          if (next case AsyncError(
            :final error,
          ) when error is DesktopReclaimedTerminal) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Desktop Took Back The Terminal')),
            );
            Navigator.of(context).pop();
          }
        },
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workspace.name, overflow: TextOverflow.ellipsis),
        bottom: tabs.value?.isNotEmpty == true
            ? PreferredSize(
                preferredSize: const Size.fromHeight(
                  AleraTokens.tabStripHeight,
                ),
                child: _TabStrip(
                  tabs: tabs.value!,
                  selectedTabId: _selectedTab(tabs.value!)?.id,
                  creating: _creating,
                  onSelect: (tab) {
                    setState(() {
                      _selectedTabId = tab.id;
                    });
                  },
                  onClose: _closeTab,
                  onCreate: _createTab,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: switch (tabs) {
          AsyncData(value: final tabList) => switch (_selectedTab(tabList)) {
            final WorkspaceTabSummary tab => TerminalTabView(
              key: ValueKey<String>(tab.id),
              hostId: widget.hostId,
              tabId: tab.id,
            ),
            null => _EmptyTabs(creating: _creating, onCreate: _createTab),
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

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.selectedTabId,
    required this.creating,
    required this.onSelect,
    required this.onClose,
    required this.onCreate,
  });

  final List<WorkspaceTabSummary> tabs;
  final String? selectedTabId;
  final bool creating;
  final ValueChanged<WorkspaceTabSummary> onSelect;
  final ValueChanged<WorkspaceTabSummary> onClose;
  final VoidCallback onCreate;

  IconData _kindIcon(String kind) {
    return switch (kind) {
      'terminal' => Icons.terminal,
      'editor' => Icons.edit_note,
      'markdownViewer' => Icons.article_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      'gitDiff' => Icons.difference_outlined,
      'browser' => Icons.public,
      _ => Icons.tab,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.tabStripHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.spaceLg,
          vertical: AleraTokens.spaceSm,
        ),
        children: <Widget>[
          for (final tab in tabs) ...<Widget>[
            InputChip(
              avatar: Icon(_kindIcon(tab.kind), size: AleraTokens.spaceLg),
              label: Text(tab.title, overflow: TextOverflow.ellipsis),
              selected: tab.id == selectedTabId,
              // Non-terminal tabs (editors, diffs, ...) are desktop surfaces;
              // they render as disabled chips on the phone for now.
              onSelected: tab.isTerminal ? (_) => onSelect(tab) : null,
              onDeleted: tab.isTerminal ? () => onClose(tab) : null,
              deleteButtonTooltipMessage: 'Close Tab',
            ),
            const SizedBox(width: AleraTokens.spaceSm),
          ],
          IconButton.filledTonal(
            tooltip: 'New Terminal Tab',
            onPressed: creating ? null : onCreate,
            icon: creating
                ? const SizedBox.square(
                    dimension: AleraTokens.spaceLg,
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeSm,
                    ),
                  )
                : const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _EmptyTabs extends StatelessWidget {
  const _EmptyTabs({required this.creating, required this.onCreate});

  final bool creating;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.terminal,
              size: AleraTokens.emptyIcon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Text('No Tabs Yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AleraTokens.spaceMd),
            FilledButton.icon(
              onPressed: creating ? null : onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create Terminal'),
            ),
          ],
        ),
      ),
    );
  }
}
