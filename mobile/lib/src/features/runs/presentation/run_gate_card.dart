import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_status.dart';
import 'package:flutter/material.dart';

/// One gate a person decides: plan approval, stage gate, stall or decision.
/// Presentational: the decision goes out through [onDecide] with the exact
/// option id the runtime accepts and, for Reject and Request Changes, the
/// required note.
class const RunGateCard({
  super.key,
  required final RunGate gate,
  required final void Function(String decision, String? reason) onDecide,
  final String? evidence,
  final bool busy = false,
  final bool stale = false,
  final bool highlighted = false,
  final VoidCallback? onRefresh,
  final VoidCallback? onViewEvidence,
}) extends StatefulWidget {
  @override
  State<RunGateCard> createState() => _RunGateCardState();
}

class _RunGateCardState extends State<RunGateCard> {
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  RunGate get _gate => widget.gate;

  bool get _enabled => !widget.busy && !widget.stale && _gate.isOpen;

  void _decide(String decision) {
    final note = _notes.text.trim();
    widget.onDecide(decision, note.isEmpty ? null : note);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final status = runGateStatusLabel(_gate.status);
    return Card(
      key: ValueKey<String>('run-gate-${_gate.id}'),
      shape: widget.highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              side: const BorderSide(color: AleraTokens.warning),
            )
          : null,
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.review,
                  size: AleraTokens.iconSm,
                  color: AleraTokens.warning,
                ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    runGateKindLabel(_gate).toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                      fontWeight: .w600,
                    ),
                  ),
                ),
                if (!_gate.isOpen)
                  AleraBadge(label: status.label, tone: status.tone),
              ],
            ),
            const SizedBox(height: AleraTokens.space8),
            Text(_question, style: theme.textTheme.bodyMedium),
            if (widget.evidence case final evidence?) ...<Widget>[
              const SizedBox(height: AleraTokens.space4),
              Text(evidence, style: muted),
            ],
            if (widget.onViewEvidence case final onViewEvidence?)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onViewEvidence,
                  child: const Text('View Evidence'),
                ),
              ),
            if (widget.stale) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              AleraNotice(
                icon: AleraIcons.warning,
                message: 'The evidence changed since you opened this gate. Review it again.',
                action: widget.onRefresh == null
                    ? null
                    : TextButton(
                        onPressed: widget.onRefresh,
                        child: const Text('Refresh'),
                      ),
              ),
            ],
            if (_gate.isOpen) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              ..._decisionControls(context),
            ] else if (_gate.resolution != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space4),
              Text(_resolutionLine, style: muted),
            ],
          ],
        ),
      ),
    );
  }

  String get _question {
    if (_gate.question.trim().isNotEmpty) return _gate.question.trim();
    return switch (_gate.kind) {
      RunGateKind.plan => 'Approving freezes this plan and starts the workers.',
      RunGateKind.stage =>
        'Approval binds this revision, integration ${shortSha(_gate.integrationSha)} and the artifact evidence below. Changed evidence needs another review.',
      RunGateKind.stall =>
        'A worker stopped reporting progress. Choose how the run continues.',
      _ => 'An agent is waiting for your decision.',
    };
  }

  String get _resolutionLine {
    final by = _gate.actorKind == null ? '' : ' by ${_gate.actorKind}';
    final reason = _gate.reason == null ? '' : ': ${_gate.reason}';
    return '${runGateOptionLabel(_gate, _gate.resolution!)}$by$reason';
  }

  List<Widget> _decisionControls(BuildContext context) => switch (_gate.kind) {
    RunGateKind.plan || RunGateKind.stage => _reviewControls(context),
    RunGateKind.stall => <Widget>[_optionButtons(runStallGateOptions)],
    _ =>
      _gate.options.isEmpty
          ? _freeTextControls()
          : <Widget>[_optionButtons(_gate.options)],
  };

  List<Widget> _reviewControls(BuildContext context) => <Widget>[
    TextField(
      key: ValueKey<String>('run-gate-notes-${_gate.id}'),
      controller: _notes,
      enabled: _enabled,
      minLines: 1,
      maxLines: 4,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        labelText: 'Notes',
        helperText: 'Required to reject or request changes.',
      ),
    ),
    const SizedBox(height: AleraTokens.space8),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton(
        onPressed: _enabled && _hasNotes
            ? () => _decide('requestChanges')
            : null,
        child: const Text('Request Changes'),
      ),
    ),
    const SizedBox(height: AleraTokens.space8),
    Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: AleraTokens.space8,
      runSpacing: AleraTokens.space8,
      children: <Widget>[
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AleraTokens.error),
          onPressed: _enabled && _hasNotes ? () => _decide('reject') : null,
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: _enabled ? () => _decide('approve') : null,
          child: widget.busy
              ? const SizedBox.square(
                  dimension: AleraTokens.iconSm,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(runGateOptionLabel(_gate, 'approve')),
        ),
      ],
    ),
  ];

  bool get _hasNotes => _notes.text.trim().isNotEmpty;

  Widget _optionButtons(List<String> options) => Wrap(
    spacing: AleraTokens.space8,
    runSpacing: AleraTokens.space8,
    children: <Widget>[
      for (final option in options)
        OutlinedButton(
          onPressed: _enabled ? () => _decide(option) : null,
          child: Text(runGateOptionLabel(_gate, option)),
        ),
    ],
  );

  List<Widget> _freeTextControls() => <Widget>[
    TextField(
      key: ValueKey<String>('run-gate-answer-${_gate.id}'),
      controller: _notes,
      enabled: _enabled,
      minLines: 1,
      maxLines: 4,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(labelText: 'Answer'),
    ),
    const SizedBox(height: AleraTokens.space8),
    Align(
      alignment: Alignment.centerRight,
      child: FilledButton(
        onPressed: _enabled && _hasNotes
            ? () => widget.onDecide(_notes.text.trim(), null)
            : null,
        child: const Text('Send Answer'),
      ),
    ),
  ];
}
