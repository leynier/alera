part of 'codex_chat_surface.dart';

extension _CodexSurfaceDialogs on _CodexChatSurfaceState {
  Future<void> _showStatus(
    BuildContext context,
    CodexChatState state,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Codex Status'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Workspace: ${state.activeCwd ?? widget.workspace.path}'),
          Text('Thread: ${widget.tab.title}'),
          Text('Model: ${state.selectedModel ?? 'Default'}'),
          Text('Reasoning: ${_choiceLabel(state.reasoningEffort)}'),
          Text('Plan Mode: ${state.planMode ? 'On' : 'Off'}'),
          Text(
            'Permissions: ${_codexPermissionModeLabel(state.permissionMode)}',
          ),
          Text('Queued Messages: ${state.queuedMessages.length}'),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _startReview(
    BuildContext context,
    CodexChatController controller,
    CodexChatState state,
  ) async {
    var branches = const <String>[];
    try {
      branches = await ref
          .read(gitBackendProvider)
          .listBranches(state.activeCwd ?? widget.workspace.path);
    } catch (_) {
      // A non-Git workspace can still use the other review targets.
    }
    if (!context.mounted) return;
    final input = TextEditingController();
    var target = 'uncommittedChanges';
    var delivery = 'inline';
    String? branch = branches.isEmpty ? null : branches.first;
    final selection = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
              if (target == 'baseBranch' && branches.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: branch,
                  decoration: const InputDecoration(labelText: 'Branch'),
                  items: <DropdownMenuItem<String>>[
                    for (final value in branches)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) => branch = value,
                )
              else if (target != 'uncommittedChanges')
                TextField(
                  controller: input,
                  decoration: InputDecoration(
                    labelText: switch (target) {
                      'baseBranch' => 'Branch',
                      'commit' => 'Commit SHA',
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
              onPressed: () => Navigator.of(context).pop(<String, String?>{
                'target': target,
                'argument': target == 'baseBranch' ? branch : input.text,
                'delivery': delivery,
              }),
              child: const Text('Start Review'),
            ),
          ],
        ),
      ),
    );
    input.dispose();
    if (selection == null || !mounted) return;
    await controller.startReview(
      target: selection['target'] ?? 'uncommittedChanges',
      argument: selection['argument'],
      delivery: selection['delivery'],
    );
  }
}
