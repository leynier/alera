part of 'codex_chat_surface.dart';

class _CodexTurnSection extends StatelessWidget {
  const _CodexTurnSection({
    required this.projection,
    required this.workspacePath,
    required this.workedExpanded,
    required this.onToggleWorked,
    required this.expandedToolGroups,
    required this.expandedToolActions,
    required this.onToggleToolGroup,
    required this.onToggleToolAction,
    required this.onOpenAttachment,
  });

  final _CodexTurnProjection projection;
  final String workspacePath;
  final bool workedExpanded;
  final VoidCallback onToggleWorked;
  final Set<String> expandedToolGroups;
  final Set<String> expandedToolActions;
  final ValueChanged<String> onToggleToolGroup;
  final ValueChanged<String> onToggleToolAction;
  final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment;

  String get turnId => projection.turnId;

  @override
  Widget build(BuildContext context) {
    Widget secondaryRow(int index) => _CodexSecondaryRow(
      key: ValueKey<String>(
        'codex-secondary-${projection.secondaryRows[index].key}',
      ),
      projection: projection.secondaryRows[index],
      groupExpanded: expandedToolGroups.contains(
        projection.secondaryRows[index].key,
      ),
      expandedToolActions: expandedToolActions,
      onToggleGroup: onToggleToolGroup,
      onToggleAction: onToggleToolAction,
      workspacePath: workspacePath,
      onOpenAttachment: onOpenAttachment,
    );
    final children = <Widget>[
      for (final cell in projection.users)
        _CodexCellView(
          cell: cell,
          workspacePath: workspacePath,
          onOpenAttachment: onOpenAttachment,
        ),
    ];
    if (projection.showWorking) {
      children.add(const _CodexWorkingIndicator());
    }
    if (projection.collapseWorked) {
      children.add(
        _WorkedForDivider(
          expanded: workedExpanded,
          label: projection.workedLabel,
          onTap: onToggleWorked,
        ),
      );
      if (workedExpanded) {
        children.addAll(<Widget>[
          for (
            var index = 0;
            index < projection.secondaryRows.length;
            index += 1
          )
            secondaryRow(index),
        ]);
      }
    } else {
      children.addAll(<Widget>[
        for (var index = 0; index < projection.secondaryRows.length; index += 1)
          secondaryRow(index),
      ]);
    }
    children.addAll(
      projection.assistants.map(
        (cell) => _CodexCellView(
          cell: cell,
          workspacePath: workspacePath,
          onOpenAttachment: onOpenAttachment,
        ),
      ),
    );
    children.addAll(
      projection.outside.map(
        (cell) => _CodexCellView(
          cell: cell,
          workspacePath: workspacePath,
          onOpenAttachment: onOpenAttachment,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
