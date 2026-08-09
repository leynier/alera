part of 'codex_chat_surface.dart';

class _CodexSecondaryRow extends StatelessWidget {
  const _CodexSecondaryRow({
    super.key,
    required this.projection,
    required this.groupExpanded,
    required this.expandedToolActions,
    required this.onToggleGroup,
    required this.onToggleAction,
    required this.workspacePath,
    required this.onOpenAttachment,
  });

  final _CodexSecondaryRowProjection projection;
  final bool groupExpanded;
  final Set<String> expandedToolActions;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<String> onToggleAction;
  final String workspacePath;
  final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment;

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
