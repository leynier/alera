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
}) extends StatelessWidget {
  String _label(String key) =>
      SimpleWorkspaceTool.forKey(key)?.label ??
      tabs
          .where((tab) => tab.id == SimpleWorkspacePanel.tabId(key))
          .firstOrNull
          ?.title ??
      'Terminal';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: <Widget>[
      SizedBox(
        height: AleraTokens.sidebarHeaderHeight,
        child: Row(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (final key in panel.tabKeys)
                      if (tabs
                              .where(
                                (tab) =>
                                    tab.id == SimpleWorkspacePanel.tabId(key),
                              )
                              .firstOrNull
                          case final WorkspaceTabRecord tab
                          when tabBuilder != null)
                        tabBuilder!(tab, panel.activeKey == key)
                      else
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: panel.activeKey == key
                                ? AleraTokens.surfaceElevated
                                : Colors.transparent,
                          ),
                          child: Row(
                            mainAxisSize: .min,
                            children: <Widget>[
                              TextButton(
                                onPressed: () => onSelect(key),
                                child: Text(_label(key)),
                              ),
                              AleraIconButton(
                                tooltip: 'Close ${_label(key)}',
                                icon: AleraIcons.close,
                                onPressed: () => onClose(key),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Add Tab',
              icon: const Icon(AleraIcons.add),
              onSelected: (key) =>
                  key == 'terminal' ? onNewTerminal() : onSelect(key),
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                for (final tool in SimpleWorkspaceTool.values)
                  AleraDropdownEntry(value: tool.key, label: tool.label),
                const AleraDropdownEntry(value: 'terminal', label: 'Terminal'),
              ],
            ),
            AleraIconButton(
              tooltip: 'Hide Panel',
              icon: AleraIcons.chevronsRight,
              onPressed: onHide,
            ),
          ],
        ),
      ),
      Expanded(
        child: panel.tabKeys.isEmpty
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
                            onPressed: () => onSelect(tool.key),
                            child: Text(tool.label),
                          ),
                        TextButton(
                          onPressed: onNewTerminal,
                          child: const Text('Terminal'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : content,
      ),
    ],
  );
}
