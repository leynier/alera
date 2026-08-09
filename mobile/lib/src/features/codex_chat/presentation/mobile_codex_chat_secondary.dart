part of 'mobile_codex_chat_screen.dart';

class _MobileQueueBar extends StatelessWidget {
  const _MobileQueueBar({required this.messages, required this.controller});

  final List<Map<String, Object?>> messages;
  final MobileCodexController controller;

  @override
  Widget build(BuildContext context) => Container(
    color: AleraTokens.surface,
    padding: const EdgeInsets.all(AleraTokens.space8),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          const Text('Queued Messages'),
          const SizedBox(width: AleraTokens.space4),
          for (final (index, message) in messages.indexed) ...<Widget>[
            InputChip(
              label: Text(
                message['text']?.toString().isNotEmpty == true
                    ? message['text'].toString()
                    : 'Attachment',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => unawaited(_edit(context, index, message)),
              onDeleted: () => controller.removeQueuedMessage(index),
            ),
            const SizedBox(width: AleraTokens.space4),
          ],
        ],
      ),
    ),
  );

  Future<void> _edit(
    BuildContext context,
    int index,
    Map<String, Object?> message,
  ) async {
    final selections = message['catalogSelections'] is List
        ? <Map<String, Object?>>[
            for (final value in message['catalogSelections']! as List)
              if (value is Map) Map<String, Object?>.from(value),
          ]
        : const <Map<String, Object?>>[];
    final value = await showDialog<_MobileQueuedMessageEdit>(
      context: context,
      builder: (context) => _MobileQueuedMessageEditor(
        initialValue: message['text']?.toString() ?? '',
        initialCatalogSelections: selections,
      ),
    );
    if (value != null) {
      controller.editQueuedMessage(
        index,
        value.text,
        catalogSelections: value.catalogSelections,
      );
    }
  }
}

class _MobileQueuedMessageEditor extends StatefulWidget {
  const _MobileQueuedMessageEditor({
    required this.initialValue,
    required this.initialCatalogSelections,
  });

  final String initialValue;
  final List<Map<String, Object?>> initialCatalogSelections;

  @override
  State<_MobileQueuedMessageEditor> createState() =>
      _MobileQueuedMessageEditorState();
}

class _MobileQueuedMessageEditorState
    extends State<_MobileQueuedMessageEditor> {
  late final TextEditingController _input;
  late TextEditingValue _lastValue;
  late List<Map<String, Object?>> _catalogSelections;

  @override
  void initState() {
    super.initState();
    _lastValue = TextEditingValue(
      text: widget.initialValue,
      selection: TextSelection.collapsed(offset: widget.initialValue.length),
    );
    _input = TextEditingController.fromValue(_lastValue);
    _catalogSelections = <Map<String, Object?>>[
      ...widget.initialCatalogSelections,
    ];
    _input.addListener(_rebaseSelections);
  }

  @override
  void dispose() {
    _input.removeListener(_rebaseSelections);
    _input.dispose();
    super.dispose();
  }

  void _rebaseSelections() {
    final next = _input.value;
    _catalogSelections = mobileCodexRebaseCatalogSelections(
      _lastValue,
      next,
      _catalogSelections,
    );
    _lastValue = next;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit Queued Message'),
    content: TextField(
      controller: _input,
      autofocus: true,
      minLines: 2,
      maxLines: AleraTokens.composeBarMaxLines,
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _MobileQueuedMessageEdit(
            text: _input.text,
            catalogSelections: mobileCodexActiveCatalogSelections(
              _input.text,
              _catalogSelections,
            ),
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}

class _MobileQueuedMessageEdit {
  const _MobileQueuedMessageEdit({
    required this.text,
    required this.catalogSelections,
  });

  final String text;
  final List<Map<String, Object?>> catalogSelections;
}

class _MobileError extends StatelessWidget {
  const _MobileError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AleraTokens.contentPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AleraTokens.space12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _MobileSendButton extends StatelessWidget {
  const _MobileSendButton({
    required this.busy,
    required this.disabled,
    required this.hasText,
    required this.canSteer,
    required this.onSend,
    required this.onSteer,
    required this.onStop,
  });

  final bool busy;
  final bool disabled;
  final bool hasText;
  final bool canSteer;
  final Future<void> Function() onSend;
  final Future<void> Function() onSteer;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final steering = busy && canSteer;
    return IconButton.filled(
      tooltip: busy ? (steering ? 'Steer' : 'Stop') : 'Send',
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(AleraTokens.space32),
        backgroundColor: busy || hasText
            ? AleraTokens.foreground
            : AleraTokens.foregroundMuted,
        foregroundColor: AleraTokens.background,
      ),
      onPressed: disabled || (!busy && !hasText)
          ? null
          : () =>
                unawaited(busy ? (steering ? onSteer() : onStop()) : onSend()),
      icon: Icon(
        busy && !steering ? Icons.stop_rounded : Icons.arrow_upward,
        size: AleraTokens.space16,
      ),
    );
  }
}

class _MobileRequestCard extends StatelessWidget {
  const _MobileRequestCard({
    required this.title,
    this.body,
    this.bodyWidget,
    required this.actions,
  });

  final String title;
  final String? body;
  final Widget? bodyWidget;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AleraTokens.surfaceElevated,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    ),
    padding: const EdgeInsets.all(AleraTokens.space12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (body != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(body!),
        ],
        if (bodyWidget != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          bodyWidget!,
        ],
        if (actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          Wrap(spacing: AleraTokens.space8, children: actions),
        ],
      ],
    ),
  );
}
