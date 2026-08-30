part of 'codex_chat_surface.dart';

class const _CodexRecoveryQuestionDock({
  super.key,
  required final String message,
  required final Future<void> Function() onContinue,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey<String>('codex-thread-recovery-dock'),
    padding: const EdgeInsets.fromLTRB(
      AleraTokens.space24,
      AleraTokens.space8,
      AleraTokens.space24,
      AleraTokens.space12,
    ),
    child: Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.codexQuestionCardMaxWidth,
        ),
        child: _CodexRecoveryQuestionCard(
          message: message,
          onContinue: onContinue,
        ),
      ),
    ),
  );
}

class const _CodexRecoveryQuestionCard({
  required final String message,
  required final Future<void> Function() onContinue,
}) extends StatefulWidget {
  @override
  State<_CodexRecoveryQuestionCard> createState() =>
      _CodexRecoveryQuestionCardState();
}

class _CodexRecoveryQuestionCardState
    extends State<_CodexRecoveryQuestionCard> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) => _CodexPromptFrame(
    frameKey: const ValueKey<String>('codex-thread-recovery'),
    header: Text(
      'Continue in a new thread?',
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: .w600),
    ),
    body: _CodexPromptOptionRow(
      index: 1,
      label: 'Continue In New Thread',
      description:
          '${widget.message.trim()} Earlier messages remain visible, but they will not be part of the new model context.',
      selected: false,
      onTap: _submitting ? null : () => unawaited(_continue()),
    ),
  );

  Future<void> _continue() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onContinue();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
