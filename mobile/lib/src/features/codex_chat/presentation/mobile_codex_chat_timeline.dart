part of 'mobile_codex_chat_screen.dart';

class _MobileTimelineCell extends StatelessWidget {
  const _MobileTimelineCell({required this.cell});

  final MobileCodexTimelineCell cell;

  @override
  Widget build(BuildContext context) {
    if (cell.kind == 'turnSeparator') {
      return const Divider(height: AleraTokens.space24);
    }
    final color = cell.isUser
        ? AleraTokens.info
        : cell.isReasoning
        ? AleraTokens.foregroundMuted
        : cell.kind == 'command' || cell.kind == 'toolCall'
        ? AleraTokens.warning
        : cell.kind == 'diff'
        ? AleraTokens.success
        : AleraTokens.foreground;
    return Card(
      color: cell.isUser ? AleraTokens.surfaceVariant : AleraTokens.surface,
      margin: const EdgeInsets.only(bottom: AleraTokens.space12),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _mobileCellLabel(cell),
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
                if (cell.isStreaming)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
              ],
            ),
            if (cell.subtitle != null)
              Text(cell.subtitle!, style: AleraTokens.monoStyle),
            const SizedBox(height: AleraTokens.space6),
            SelectableText(
              cell.displayText,
              style: TextStyle(color: color, height: 1.4),
            ),
            if (cell.status == 'failed')
              Text(
                'Codex could not complete this item.',
                style: TextStyle(color: AleraTokens.error),
              ),
          ],
        ),
      ),
    );
  }
}

class _MobileApprovalCard extends StatelessWidget {
  const _MobileApprovalCard({required this.request, required this.controller});

  final MobileCodexPendingRequest request;
  final MobileCodexController controller;

  @override
  Widget build(BuildContext context) => _MobileRequestCard(
    title: 'Codex Needs Approval',
    body: request.description,
    actions: <Widget>[
      TextButton(
        onPressed: () =>
            unawaited(controller.respondApproval(request, accepted: false)),
        child: const Text('Decline'),
      ),
      FilledButton(
        onPressed: () =>
            unawaited(controller.respondApproval(request, accepted: true)),
        child: const Text('Approve'),
      ),
      TextButton(
        onPressed: () => unawaited(
          controller.respondApproval(request, accepted: true, forSession: true),
        ),
        child: const Text('Approve For Session'),
      ),
    ],
  );
}

class _MobileQuestionCard extends StatefulWidget {
  const _MobileQuestionCard({required this.request, required this.controller});

  final MobileCodexPendingRequest request;
  final MobileCodexController controller;

  @override
  State<_MobileQuestionCard> createState() => _MobileQuestionCardState();
}

class _MobileQuestionCardState extends State<_MobileQuestionCard> {
  final Map<String, TextEditingController> _text =
      <String, TextEditingController>{};
  final Map<String, Set<String>> _selected = <String, Set<String>>{};

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.request.questions;
    return _MobileRequestCard(
      title: 'Codex Needs Your Input',
      bodyWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final question in questions) _question(question),
        ],
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => unawaited(
            widget.controller.respondQuestion(
              widget.request,
              <String, List<String>>{
                for (final question in questions)
                  question.id:
                      question.isOther &&
                          (_text[question.id]?.text.trim().isNotEmpty ?? false)
                      ? <String>[_text[question.id]!.text.trim()]
                      : _selected[question.id]?.isNotEmpty == true
                      ? _selected[question.id]!.toList(growable: false)
                      : <String>[_text[question.id]?.text.trim() ?? ''],
              },
            ),
          ),
          child: const Text('Submit Answers'),
        ),
      ],
    );
  }

  Widget _question(MobileCodexQuestion question) {
    final text = _text.putIfAbsent(question.id, TextEditingController.new);
    final selected = _selected.putIfAbsent(question.id, () => <String>{});
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            question.header ?? question.question,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (question.header != null) Text(question.question),
          if (question.options.isNotEmpty)
            Wrap(
              spacing: AleraTokens.space4,
              children: <Widget>[
                for (final option in question.options)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: selected.contains(option.label),
                    onSelected: (value) => setState(() {
                      if (!question.isMultiSelect) selected.clear();
                      if (value) {
                        selected.add(option.label);
                      } else {
                        selected.remove(option.label);
                      }
                    }),
                  ),
              ],
            ),
          if (question.options.isEmpty || question.isOther)
            TextField(
              controller: text,
              obscureText: question.isSecret,
              decoration: const InputDecoration(hintText: 'Your Answer'),
            ),
        ],
      ),
    );
  }
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

String _mobileCellLabel(MobileCodexTimelineCell cell) {
  if (cell.isUser) return 'You';
  if (cell.isAssistant) return 'Codex';
  if (cell.isReasoning) return 'Reasoning';
  if (cell.kind == 'command') return cell.title ?? 'Command';
  if (cell.kind == 'toolCall') return cell.title ?? 'Tool Call';
  if (cell.kind == 'diff') return cell.title ?? 'File Changes';
  if (cell.kind == 'plan') return 'Plan';
  if (cell.kind == 'subAgent') return cell.title ?? 'Sub-Agent';
  return cell.title ?? 'Codex Activity';
}

String _mobileLabel(String value) => value
    .split('-')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
