part of 'codex_chat_surface.dart';

class _CodexSecondaryRow extends StatelessWidget {
  const _CodexSecondaryRow({
    required this.projection,
    required this.workspacePath,
    required this.onOpenAttachment,
  });

  final _CodexSecondaryRowProjection projection;
  final String workspacePath;
  final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (projection.isGroup) {
      child = _CodexWorkedActionGroup(projection: projection);
    } else if (projection.isWorked) {
      child = _CodexWorkedActionRow(action: projection.actions.single);
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
