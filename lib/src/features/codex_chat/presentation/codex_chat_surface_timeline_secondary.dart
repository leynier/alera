part of 'codex_chat_surface.dart';

class const _CodexSecondaryRow({
  super.key,
  required final _CodexSecondaryRowProjection projection,
  required final bool groupExpanded,
  required final Set<String> expandedToolActions,
  required final ValueChanged<String> onToggleGroup,
  required final ValueChanged<String> onToggleAction,
  required final String workspacePath,
  required final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (projection.isGroup) {
      child = _CodexWorkedActionGroup(
        projection: projection,
        expanded: groupExpanded,
        expandedActions: expandedToolActions,
        onToggle: () => onToggleGroup(projection.key),
        onToggleAction: onToggleAction,
      );
    } else if (projection.isWorked) {
      final action = projection.actions.single;
      child = _CodexWorkedActionRow(
        action: action,
        expanded: expandedToolActions.contains(action.cell.id),
        onToggle: () => onToggleAction(action.cell.id),
      );
    } else {
      child = _CodexCellView(
        cell: projection.cell!,
        workspacePath: workspacePath,
        onOpenAttachment: onOpenAttachment,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
      child: child,
    );
  }
}
