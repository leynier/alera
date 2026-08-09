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
  final input = TextEditingController();
  var target = 'uncommittedChanges';
  var delivery = 'inline';
  final selection = await showDialog<Map<String, String?>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final requiresArgument = target != 'uncommittedChanges';
        final canSubmit = !requiresArgument || input.text.trim().isNotEmpty;
        return AlertDialog(
          title: const Text('Start Review'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: target,
                decoration: const InputDecoration(labelText: 'Target'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'uncommittedChanges',
                    child: Text('Uncommitted Changes'),
                  ),
                  DropdownMenuItem(
                    value: 'baseBranch',
                    child: Text('Base Branch'),
                  ),
                  DropdownMenuItem(value: 'commit', child: Text('Commit')),
                  DropdownMenuItem(value: 'custom', child: Text('Custom')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => target = value);
                },
              ),
              if (target != 'uncommittedChanges')
                TextField(
                  controller: input,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: switch (target) {
                      'baseBranch' => 'Branch',
                      'commit' => 'Commit Sha',
                      _ => 'Instructions',
                    },
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: delivery,
                decoration: const InputDecoration(labelText: 'Delivery'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'inline', child: Text('Inline')),
                  DropdownMenuItem(value: 'detached', child: Text('Detached')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => delivery = value);
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: canSubmit
                  ? () => Navigator.of(context).pop(<String, String?>{
                      'target': target,
                      'argument': input.text.trim(),
                      'delivery': delivery,
                    })
                  : null,
              child: const Text('Start Review'),
            ),
          ],
        );
      },
    ),
  );
  input.dispose();
  if (selection == null || !context.mounted) return;
  await controller.review(
    target: selection['target'] ?? 'uncommittedChanges',
    argument: selection['argument'],
    delivery: selection['delivery'],
  );
}
