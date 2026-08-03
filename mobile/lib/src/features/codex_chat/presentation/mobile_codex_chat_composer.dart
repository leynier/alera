part of 'mobile_codex_chat_screen.dart';

class _MobileRequestCard extends StatelessWidget {
  const _MobileRequestCard({
    this.title = 'Codex Request',
    this.body,
    this.bodyWidget,
    required this.actions,
  });

  final String title;
  final String? body;
  final Widget? bodyWidget;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
    color: AleraTokens.surfaceElevated,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (body != null)
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space6),
              child: Text(body!),
            ),
          if (bodyWidget != null)
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space6),
              child: bodyWidget!,
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space8),
              child: Wrap(spacing: AleraTokens.space8, children: actions),
            ),
        ],
      ),
    ),
  );
}

class _MobileQueueBar extends StatelessWidget {
  const _MobileQueueBar({required this.messages, required this.controller});

  final List<Map<String, Object?>> messages;
  final MobileCodexController controller;

  @override
  Widget build(BuildContext context) => Container(
    color: AleraTokens.surface,
    padding: const EdgeInsets.all(AleraTokens.space8),
    child: Wrap(
      spacing: AleraTokens.space4,
      children: <Widget>[
        const Text('Queued Messages'),
        for (final (index, message) in messages.indexed)
          InputChip(
            label: Text(
              message['text']?.toString().isNotEmpty == true
                  ? message['text'].toString()
                  : 'Attachment',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () =>
                _edit(context, index, message['text']?.toString() ?? ''),
            onDeleted: () => controller.removeQueuedMessage(index),
          ),
      ],
    ),
  );

  Future<void> _edit(BuildContext context, int index, String initial) async {
    final input = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Queued Message'),
        content: TextField(controller: input, autofocus: true, maxLines: 4),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null) controller.editQueuedMessage(index, value);
  }
}

class _MobileComposer extends StatelessWidget {
  const _MobileComposer({
    required this.controller,
    required this.attachments,
    required this.busy,
    required this.interrupting,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onSteer,
    required this.onStop,
    required this.canAttach,
  });

  final TextEditingController controller;
  final List<Map<String, Object?>> attachments;
  final bool busy;
  final bool interrupting;
  final Future<void> Function() onAttach;
  final ValueChanged<Map<String, Object?>> onRemoveAttachment;
  final Future<void> Function() onSend;
  final Future<void> Function() onSteer;
  final Future<void> Function() onStop;
  final bool canAttach;

  @override
  Widget build(BuildContext context) => Padding(
    padding: AleraTokens.contentPadding,
    child: Column(
      children: <Widget>[
        if (attachments.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: AleraTokens.space4,
              children: <Widget>[
                for (final attachment in attachments)
                  InputChip(
                    label: Text(
                      attachment['path']?.toString().split('/').last ?? 'Image',
                    ),
                    onDeleted: () => onRemoveAttachment(attachment),
                  ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            IconButton(
              tooltip: 'Attach Image',
              onPressed: canAttach ? () => unawaited(onAttach()) : null,
              icon: const Icon(Icons.image_outlined),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: AleraTokens.composeBarMaxLines,
                decoration: const InputDecoration(hintText: 'Message Codex'),
              ),
            ),
            if (busy)
              IconButton(
                tooltip: 'Steer',
                onPressed: () => unawaited(onSteer()),
                icon: const Icon(Icons.alt_route),
              )
            else
              const SizedBox(width: AleraTokens.minTapTarget),
            IconButton.filled(
              tooltip: busy ? 'Stop' : 'Send',
              onPressed: interrupting
                  ? null
                  : () => unawaited(busy ? onStop() : onSend()),
              icon: Icon(busy ? Icons.stop : Icons.send),
            ),
          ],
        ),
      ],
    ),
  );
}
