part of 'codex_chat_surface.dart';

class const _CodexTurnSection({
  required final _CodexTurnProjection projection,
  required final String workspacePath,
  required final bool workedExpanded,
  required final VoidCallback onToggleWorked,
  required final Set<String> expandedToolGroups,
  required final Set<String> expandedToolActions,
  required final ValueChanged<String> onToggleToolGroup,
  required final ValueChanged<String> onToggleToolAction,
  required final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment,
}) extends StatelessWidget {
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
    children.add(
      _WorkedForDivider(
        expanded: workedExpanded,
        label: projection.workedLabel,
        working: projection.working,
        startedAt: projection.startedAt,
        canToggle: projection.canToggleWorked,
        onTap: onToggleWorked,
      ),
    );
    if (workedExpanded) {
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
      child: Column(crossAxisAlignment: .stretch, children: children),
    );
  }
}
