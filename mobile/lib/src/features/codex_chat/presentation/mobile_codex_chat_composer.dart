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
    required this.focusNode,
    required this.state,
    required this.attachments,
    required this.busy,
    required this.interrupting,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onSteer,
    required this.onStop,
    required this.canAttach,
    required this.onModel,
    required this.onReasoning,
    required this.onSpeed,
    required this.onPermission,
    required this.onPlan,
    required this.onCollaboration,
    required this.onInsertToken,
    required this.onCompact,
    required this.onReview,
    required this.onRename,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final MobileCodexState state;
  final List<Map<String, Object?>> attachments;
  final bool busy;
  final bool interrupting;
  final Future<void> Function() onAttach;
  final ValueChanged<Map<String, Object?>> onRemoveAttachment;
  final Future<void> Function() onSend;
  final Future<void> Function() onSteer;
  final Future<void> Function() onStop;
  final bool canAttach;
  final ValueChanged<String?> onModel;
  final ValueChanged<String> onReasoning;
  final ValueChanged<String> onSpeed;
  final ValueChanged<String> onPermission;
  final ValueChanged<bool> onPlan;
  final ValueChanged<String?> onCollaboration;
  final ValueChanged<String> onInsertToken;
  final Future<void> Function() onCompact;
  final Future<void> Function() onReview;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) => Padding(
    padding: AleraTokens.contentPadding,
    child: Column(
      children: <Widget>[
        _MobileComposerOptions(
          state: state,
          onModel: onModel,
          onReasoning: onReasoning,
          onSpeed: onSpeed,
          onPermission: onPermission,
          onPlan: onPlan,
          onCollaboration: onCollaboration,
          onInsertToken: onInsertToken,
          onCompact: onCompact,
          onReview: onReview,
          onRename: onRename,
        ),
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
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.enter): () =>
                      unawaited(busy ? onSteer() : onSend()),
                  const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                      _insertLineBreak,
                },
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !interrupting,
                  minLines: 1,
                  maxLines: AleraTokens.composeBarMaxLines,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(hintText: 'Message Codex'),
                ),
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

  void _insertLineBreak() {
    if (interrupting) return;
    final value = controller.value;
    final start = value.selection.start < 0
        ? value.text.length
        : value.selection.start;
    final end = value.selection.end < 0
        ? value.text.length
        : value.selection.end;
    controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }
}

class _MobileComposerOptions extends StatelessWidget {
  const _MobileComposerOptions({
    required this.state,
    required this.onModel,
    required this.onReasoning,
    required this.onSpeed,
    required this.onPermission,
    required this.onPlan,
    required this.onCollaboration,
    required this.onInsertToken,
    required this.onCompact,
    required this.onReview,
    required this.onRename,
  });

  final MobileCodexState state;
  final ValueChanged<String?> onModel;
  final ValueChanged<String> onReasoning;
  final ValueChanged<String> onSpeed;
  final ValueChanged<String> onPermission;
  final ValueChanged<bool> onPlan;
  final ValueChanged<String?> onCollaboration;
  final ValueChanged<String> onInsertToken;
  final Future<void> Function() onCompact;
  final Future<void> Function() onReview;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final model = state.models
        .where((item) => item.id == state.selectedModel)
        .firstOrNull;
    final reasoning = model?.reasoningEfforts.isNotEmpty == true
        ? model!.reasoningEfforts
        : const <String>['low', 'medium', 'high', 'xhigh'];
    final speeds = model?.supportsFastMode == true
        ? const <String>['normal', 'fast']
        : const <String>['normal'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          DropdownButton<String>(
            value: state.models.any((item) => item.id == state.selectedModel)
                ? state.selectedModel
                : null,
            hint: const Text('Model'),
            items: <DropdownMenuItem<String>>[
              for (final item in state.models)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.label),
                ),
            ],
            onChanged: onModel,
          ),
          _MobileOptionButton(
            label: 'Reasoning: ${_mobileLabel(state.reasoningEffort)}',
            values: reasoning,
            onSelected: onReasoning,
          ),
          _MobileOptionButton(
            label: 'Speed: ${_mobileLabel(state.speedMode)}',
            values: speeds,
            onSelected: onSpeed,
          ),
          _MobileOptionButton(
            label: 'Permission: ${_mobileLabel(state.permissionMode)}',
            values: const <String>['on-request', 'never'],
            onSelected: onPermission,
          ),
          FilterChip(
            label: const Text('Plan'),
            selected: state.planMode,
            onSelected: onPlan,
          ),
          if (state.collaborationModes.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Collaboration Mode',
              onSelected: onCollaboration,
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                for (final mode in state.collaborationModes)
                  if (mode['mode']?.toString().trim() case final String value
                      when value.isNotEmpty)
                    PopupMenuItem<String>(
                      value: value,
                      child: Text(_mobileLabel(value)),
                    ),
              ],
              child: TextButton(
                onPressed: null,
                child: Text(
                  state.collaborationMode == null
                      ? 'Collaboration'
                      : _mobileLabel(state.collaborationMode!),
                ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Skills',
            onSelected: (value) => onInsertToken('/skill $value'),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              for (final item in state.skills)
                if (item['name']?.toString().trim() case final String value
                    when value.isNotEmpty)
                  PopupMenuItem<String>(value: value, child: Text(value)),
            ],
            child: TextButton(onPressed: null, child: const Text('Skills')),
          ),
          PopupMenuButton<String>(
            tooltip: 'Apps',
            onSelected: (value) => onInsertToken('/app $value'),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              for (final item in state.apps)
                if (item['name']?.toString().trim() case final String value
                    when value.isNotEmpty)
                  PopupMenuItem<String>(value: value, child: Text(value)),
            ],
            child: TextButton(onPressed: null, child: const Text('Apps')),
          ),
          IconButton(
            tooltip: 'Compact Context',
            onPressed: () => unawaited(onCompact()),
            icon: const Icon(Icons.compress),
          ),
          IconButton(
            tooltip: 'Start Review',
            onPressed: () => unawaited(onReview()),
            icon: const Icon(Icons.rate_review_outlined),
          ),
          IconButton(
            tooltip: 'Rename Thread',
            onPressed: onRename,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

class _MobileOptionButton extends StatelessWidget {
  const _MobileOptionButton({
    required this.label,
    required this.values,
    required this.onSelected,
  });

  final String label;
  final List<String> values;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: label,
    onSelected: onSelected,
    itemBuilder: (context) => <PopupMenuEntry<String>>[
      for (final value in values)
        PopupMenuItem<String>(value: value, child: Text(_mobileLabel(value))),
    ],
    child: TextButton(onPressed: null, child: Text(label)),
  );
}

String _mobileLabel(String value) => value
    .split('-')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
