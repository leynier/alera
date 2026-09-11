import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/workbench/domain/experimental_workspace_panel.dart';
import 'package:flutter/material.dart';

/// Chooses which Experimental tools open, and in what order, on a new workspace.
class ExperimentalNewWorkspaceToolsSettings extends StatefulWidget {
  const ExperimentalNewWorkspaceToolsSettings({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final List<ExperimentalWorkspaceTool> selected;
  final ValueChanged<List<ExperimentalWorkspaceTool>> onChanged;

  @override
  State<ExperimentalNewWorkspaceToolsSettings> createState() =>
      _ExperimentalNewWorkspaceToolsSettingsState();
}

class _ExperimentalNewWorkspaceToolsSettingsState
    extends State<ExperimentalNewWorkspaceToolsSettings> {
  late List<ExperimentalWorkspaceTool> _order;

  @override
  void initState() {
    super.initState();
    _order = ExperimentalWorkspaceTool.settingsOrder(widget.selected);
  }

  @override
  void didUpdateWidget(ExperimentalNewWorkspaceToolsSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sameTools(oldWidget.selected, widget.selected)) {
      return;
    }
    final selectedSet = widget.selected.toSet();
    final fromOrder = <ExperimentalWorkspaceTool>[
      for (final tool in _order)
        if (selectedSet.contains(tool)) tool,
    ];
    if (_sameTools(fromOrder, widget.selected) &&
        _order.toSet().containsAll(ExperimentalWorkspaceTool.values)) {
      return;
    }
    _order = ExperimentalWorkspaceTool.settingsOrder(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selected.toSet();
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Text(
            'New Workspace Tools',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: .w500,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            'Open these tools in the right panel of workspaces created while Experimental Mode is on. Drag to change their order. Existing workspaces keep their own panel.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space12),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _order.length,
            onReorderItem: _reorder,
            itemBuilder: (context, index) {
              final tool = _order[index];
              return Padding(
                key: ValueKey<ExperimentalWorkspaceTool>(tool),
                padding: const EdgeInsets.symmetric(
                  vertical: AleraTokens.space4,
                ),
                child: Row(
                  children: <Widget>[
                    AleraCheckbox(
                      value: selected.contains(tool),
                      label: tool.label,
                      onChanged: (value) => _toggle(tool, value),
                    ),
                    const Spacer(),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Icon(
                        AleraIcons.dragHandle,
                        size: AleraTokens.iconLg,
                        color: AleraTokens.foregroundFaint,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _reorder(int fromIndex, int toIndex) {
    setState(() {
      final tool = _order.removeAt(fromIndex);
      _order.insert(toIndex.clamp(0, _order.length), tool);
    });
    _emit(widget.selected.toSet());
  }

  void _toggle(ExperimentalWorkspaceTool tool, bool enabled) {
    final next = <ExperimentalWorkspaceTool>{...widget.selected.toSet()};
    if (enabled) {
      next.add(tool);
    } else {
      next.remove(tool);
    }
    _emit(next);
  }

  void _emit(Set<ExperimentalWorkspaceTool> selected) {
    widget.onChanged(
      ExperimentalWorkspaceTool.selectedFromOrder(
        order: _order,
        selected: selected,
      ),
    );
  }

  static bool _sameTools(
    List<ExperimentalWorkspaceTool> left,
    List<ExperimentalWorkspaceTool> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }
}
