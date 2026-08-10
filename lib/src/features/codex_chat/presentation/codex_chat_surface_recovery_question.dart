part of 'codex_chat_surface.dart';

class _CodexRecoveryQuestionDock extends StatelessWidget {
  const _CodexRecoveryQuestionDock({
    super.key,
    required this.message,
    required this.onContinue,
  });

  final String message;
  final Future<void> Function() onContinue;

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

class _CodexRecoveryQuestionCard extends StatefulWidget {
  const _CodexRecoveryQuestionCard({
    required this.message,
    required this.onContinue,
  });

  final String message;
  final Future<void> Function() onContinue;

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
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
