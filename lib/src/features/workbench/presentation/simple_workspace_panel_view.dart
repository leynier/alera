import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/workbench/domain/simple_workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/material.dart';

class const SimpleWorkspacePanelView({
  super.key,
  required final SimpleWorkspacePanel panel,
  required final List<WorkspaceTabRecord> tabs,
  required final ValueChanged<String> onSelect,
  required final ValueChanged<String> onClose,
  required final VoidCallback onNewTerminal,
  required final VoidCallback onHide,
  required final Widget content,
  final Widget Function(WorkspaceTabRecord tab, bool active)? tabBuilder,
}) extends StatefulWidget {
  @override
  State<SimpleWorkspacePanelView> createState() =>
      _SimpleWorkspacePanelViewState();
}

class _SimpleWorkspacePanelViewState extends State<SimpleWorkspacePanelView> {
  final ScrollController _scrollController = ScrollController();
  bool _hasOverflow = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncOverflow() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final overflow = _scrollController.position.maxScrollExtent > 0.5;
    if (overflow != _hasOverflow) {
      setState(() => _hasOverflow = overflow);
    }
  }

  Widget _tabChip(String key) {
    final tab = widget.tabs
        .where((tab) => tab.id == SimpleWorkspacePanel.tabId(key))
        .firstOrNull;
    if (tab != null && widget.tabBuilder != null) {
      return widget.tabBuilder!(tab, widget.panel.activeKey == key);
    }
    final tool = SimpleWorkspaceTool.forKey(key);
    final label = tool?.label ?? 'Terminal';
    return Padding(
      padding: const EdgeInsets.only(right: AleraTokens.space8),
      child: _SimplePanelToolChip(
        label: label,
        icon: _iconForTool(tool),
        active: widget.panel.activeKey == key,
        onSelect: () => widget.onSelect(key),
        onClose: () => widget.onClose(key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
    final openKeys = widget.panel.tabKeys.toSet();
    final addButton = _SimplePanelAddButton(
      availableTools: <SimpleWorkspaceTool>[
        for (final tool in SimpleWorkspaceTool.values)
          if (!openKeys.contains(tool.key)) tool,
      ],
      onSelect: widget.onSelect,
      onNewTerminal: widget.onNewTerminal,
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        SizedBox(
          height: AleraTokens.sidebarHeaderHeight,
          child: Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space8,
                    vertical: AleraTokens.space6,
                  ),
                  child: Row(
                    mainAxisSize: .min,
                    children: <Widget>[
                      for (final key in widget.panel.tabKeys) _tabChip(key),
                      if (!_hasOverflow) addButton,
                    ],
                  ),
                ),
              ),
              if (_hasOverflow)
                Padding(
                  padding: const EdgeInsets.only(right: AleraTokens.space8),
                  child: addButton,
                ),
              AleraIconButton(
                tooltip: 'Hide Panel',
                icon: AleraIcons.chevronsRight,
                onPressed: widget.onHide,
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.panel.tabKeys.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(AleraTokens.space16),
                      child: Column(
                        mainAxisSize: .min,
                        children: <Widget>[
                          const Text('Add a tool or terminal to this panel.'),
                          const SizedBox(height: AleraTokens.space12),
                          for (final tool in SimpleWorkspaceTool.values)
                            TextButton(
                              onPressed: () => widget.onSelect(tool.key),
                              child: Text(tool.label),
                            ),
                          TextButton(
                            onPressed: widget.onNewTerminal,
                            child: const Text('Terminal'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : widget.content,
        ),
      ],
    );
  }
}

IconData _iconForTool(SimpleWorkspaceTool? tool) {
  return switch (tool) {
    SimpleWorkspaceTool.explorer => AleraIcons.folder,
    SimpleWorkspaceTool.search => AleraIcons.search,
    SimpleWorkspaceTool.sourceControl => AleraIcons.gitBranch,
    SimpleWorkspaceTool.pullRequest => AleraIcons.gitPullRequest,
    null => AleraIcons.terminal,
  };
}

class const _SimplePanelToolChip({
  required final String label,
  required final IconData icon,
  required final bool active,
  required final VoidCallback onSelect,
  required final VoidCallback onClose,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = active ? AleraTokens.foreground : AleraTokens.foregroundMuted;
    return Material(
      color: active ? AleraTokens.surfaceElevated : AleraTokens.surface,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: InkWell(
        onTap: onSelect,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: .circular(AleraTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space6,
            vertical: AleraTokens.space6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(
              color: active ? AleraTokens.border : AleraTokens.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: AleraTokens.space4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 92),
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: .ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: color),
                ),
              ),
              const SizedBox(width: AleraTokens.space4),
              InkWell(
                onTap: onClose,
                mouseCursor: SystemMouseCursors.click,
                borderRadius: .circular(AleraTokens.radiusSm),
                child: Tooltip(
                  message: 'Close $label',
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      AleraIcons.close,
                      size: 12,
                      color: AleraTokens.foregroundMuted,
                    ),
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

class const _SimplePanelAddButton({
  required final List<SimpleWorkspaceTool> availableTools,
  required final ValueChanged<String> onSelect,
  required final VoidCallback onNewTerminal,
}) extends StatelessWidget {
  Future<void> _openMenu(BuildContext context) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(
      button.size.bottomLeft(.zero),
      ancestor: overlay,
    );
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<String>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        for (final tool in availableTools)
          AleraDropdownEntry(value: tool.key, label: tool.label),
        const AleraDropdownEntry(value: 'terminal', label: 'Terminal'),
      ],
    );
    if (selected == null) {
      return;
    }
    if (selected == 'terminal') {
      onNewTerminal();
      return;
    }
    onSelect(selected);
  }

  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: 'Add Tab',
      icon: AleraIcons.add,
      iconSize: 16,
      minSize: 28,
      hoverColor: AleraTokens.surfaceElevated,
      borderRadius: AleraTokens.radiusSm,
      onPressed: () => unawaited(_openMenu(context)),
    );
  }
}
