part of 'codex_chat_surface.dart';

class const _CodexPlanQuestionCard({
  super.key,
  required final VoidCallback onInteraction,
  required final Future<void> Function() onImplement,
  required final Future<void> Function() onDecline,
  required final Future<void> Function(String refinement) onRefine,
}) extends StatefulWidget {
  @override
  State<_CodexPlanQuestionCard> createState() => _CodexPlanQuestionCardState();
}

class _CodexPlanQuestionCardState extends State<_CodexPlanQuestionCard> {
  final TextEditingController _refinement = TextEditingController();
  bool _refining = false;
  bool _submitting = false;

  @override
  void dispose() {
    _refinement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CodexPromptFrame(
    frameKey: const ValueKey<String>('codex-plan-question-card'),
    header: _CodexPromptHeader(
      title: 'Implement this plan?',
      onClose: _submitting ? null : _decline,
      closeTooltip: 'Decline Plan',
    ),
    body: Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _CodexPromptOptionRow(
          index: 1,
          label: 'Yes, implement this plan',
          selected: false,
          onTap: _submitting ? null : _implement,
        ),
        if (_refining)
          _CodexPromptInlineAnswerRow(
            controller: _refinement,
            hintText: 'Tell Codex what to do differently',
            actionLabel: 'Submit',
            onChanged: () => setState(() {}),
            onSkip: _submitting ? null : _decline,
            onSubmit: _submitting ? null : () => _refine(_refinement.text),
          )
        else
          _CodexPromptOptionRow.other(
            label: 'No, and tell Codex what to do differently',
            selected: false,
            onTap: _submitting
                ? null
                : () {
                    widget.onInteraction();
                    setState(() => _refining = true);
                  },
            trailing: _CodexSkipButton(
              onPressed: _submitting ? null : _decline,
            ),
          ),
      ],
    ),
  );

  Future<void> _implement() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    await widget.onImplement();
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _decline() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    await widget.onDecline();
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _refine(String value) async {
    final refinement = value.trim();
    if (_submitting || refinement.isEmpty) return;
    setState(() => _submitting = true);
    await widget.onRefine(refinement);
    if (mounted) setState(() => _submitting = false);
  }
}
