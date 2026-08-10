part of 'mobile_codex_chat_screen.dart';

Future<void> _showMobileRenameDialog(
  BuildContext context,
  MobileCodexController controller,
  String? current,
) async {
  final input = TextEditingController(text: current ?? 'Codex Chat');
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename Codex Chat'),
      content: TextField(controller: input, autofocus: true),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(input.text),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  input.dispose();
  if (value != null && value.trim().isNotEmpty) {
    await controller.rename(value);
  }
}

Future<void> _showMobileReviewDialog(
  BuildContext context,
  MobileCodexController controller,
) async {
  final branches = controller.reviewBranches();
  final selection = await showModalBottomSheet<_MobileCodexReviewSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AleraTokens.surface,
    builder: (context) => _MobileCodexReviewSheet(branches: branches),
  );
  if (selection == null || !context.mounted) return;
  await controller.review(
    target: selection.target.wireValue,
    argument: selection.argument,
    commitTitle: selection.commitTitle,
    delivery: selection.delivery.wireValue,
  );
}
