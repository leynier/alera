import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:flutter/material.dart';

/// One answer of an [AleraGateCard]. [requiresNotes] keeps the option
/// disabled until the notes field holds text; [busyLabel] replaces the label
/// while the answer is being sent.
class const AleraGateCardOption({
  required final String id,
  required final String label,
  final String? busyLabel,
  final bool primary = false,
  final bool destructive = false,
  final bool requiresNotes = false,
});

/// A decision a person owes a run: stage gates, plan approvals, agent
/// questions and stalls. Shows what is being asked, the evidence to read, and
/// the answers, and refuses an answer while the gate is stale, busy or not
/// due yet.
class const AleraGateCard({
  super.key,
  required final String kindLabel,
  final String? title,
  required final String statusLabel,
  final AleraBadgeTone statusTone = AleraBadgeTone.attention,
  final String? statusDetail,
  required final String prompt,
  final String? meta,
  final List<Widget> links = const <Widget>[],
  final Widget? body,
  final List<AleraGateCardOption> options = const <AleraGateCardOption>[],
  final String? notesLabel,
  final bool allowOther = false,
  final String otherLabel = 'Other…',
  final String otherHint = 'Type an answer',
  final String sendOtherLabel = 'Send Answer',
  final String sendingOtherLabel = 'Sending…',
  final String? busyOptionId,
  final bool stale = false,
  final String staleMessage =
      'This gate changed while you were reading. Refresh before deciding.',
  final String refreshLabel = 'Refresh',
  final VoidCallback? onRefresh,
  final String? error,
  final bool enabled = true,
  required final void Function(String optionId, String notes) onSelected,
}) extends StatefulWidget {
  /// Option id reported to [onSelected] for a free-text answer, with the
  /// typed answer as its notes.
  static const String otherOptionId = '__other__';

  @override
  State<AleraGateCard> createState() => _AleraGateCardState();
}

class _AleraGateCardState extends State<AleraGateCard> {
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _other = TextEditingController();
  bool _otherOpen = false;

  @override
  void dispose() {
    _notes.dispose();
    _other.dispose();
    super.dispose();
  }

  bool get _busy => widget.busyOptionId != null;

  bool get _locked => !widget.enabled || widget.stale || _busy;

  void _refresh(String _) => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final radius = BorderRadius.circular(AleraTokens.radiusLg);
    final title = widget.title;
    final statusDetail = widget.statusDetail;
    final meta = widget.meta;
    final body = widget.body;
    final error = widget.error;
    final notesLabel = widget.notesLabel;
    final content = Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${widget.kindLabel.toUpperCase()}'
                '${title == null ? '' : ' · $title'}',
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontWeight: .w600,
                ),
              ),
            ),
            if (statusDetail != null) ...<Widget>[
              const SizedBox(width: AleraTokens.space8),
              Text(statusDetail, maxLines: 1, style: muted),
            ],
            const SizedBox(width: AleraTokens.space8),
            AleraBadge(label: widget.statusLabel, tone: widget.statusTone),
          ],
        ),
        const SizedBox(height: AleraTokens.space8),
        SelectableText(
          widget.prompt,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foreground,
          ),
        ),
        if (meta != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(meta, style: muted),
        ],
        if (widget.links.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Wrap(
            spacing: AleraTokens.space4,
            runSpacing: AleraTokens.space4,
            children: widget.links,
          ),
        ],
        if (body != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          body,
        ],
        if (widget.stale) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          AleraInlineNotice(
            message: widget.staleMessage,
            tone: .warning,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                key: const ValueKey<String>('gateRefresh'),
                onPressed: widget.onRefresh,
                child: Text(widget.refreshLabel),
              ),
            ),
          ),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          AleraInlineNotice(message: error, tone: .error),
        ],
        if (notesLabel != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          AleraTextField(
            key: const ValueKey<String>('gateNotes'),
            controller: _notes,
            labelText: notesLabel,
            enabled: !_busy,
            minLines: 1,
            maxLines: 4,
            onChanged: _refresh,
          ),
        ],
        if (widget.options.isNotEmpty || widget.allowOther) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          Wrap(
            alignment: .end,
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: <Widget>[
              if (widget.allowOther)
                TextButton(
                  key: const ValueKey<String>('gateOtherToggle'),
                  onPressed: _locked
                      ? null
                      : () => setState(() => _otherOpen = !_otherOpen),
                  child: Text(widget.otherLabel),
                ),
              for (final option in widget.options) _optionButton(option),
            ],
          ),
        ],
        if (widget.allowOther && _otherOpen) ..._otherAnswer(),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: radius,
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: widget.statusTone.foreground,
                width: AleraTokens.strokeSm,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _optionButton(AleraGateCardOption option) {
    final missingNotes = option.requiresNotes && _notes.text.trim().isEmpty;
    final onPressed = _locked || missingNotes
        ? null
        : () => widget.onSelected(option.id, _notes.text.trim());
    final pressed = widget.busyOptionId == option.id;
    final label = Text(
      pressed ? option.busyLabel ?? option.label : option.label,
    );
    final key = ValueKey<String>('gateOption:${option.id}');
    if (option.destructive) {
      return OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(foregroundColor: AleraTokens.error),
        child: label,
      );
    }
    if (option.primary) {
      return FilledButton(key: key, onPressed: onPressed, child: label);
    }
    return OutlinedButton(key: key, onPressed: onPressed, child: label);
  }

  List<Widget> _otherAnswer() {
    final answer = _other.text.trim();
    final sending = widget.busyOptionId == AleraGateCard.otherOptionId;
    return <Widget>[
      const SizedBox(height: AleraTokens.space12),
      AleraTextField(
        key: const ValueKey<String>('gateOtherField'),
        controller: _other,
        hintText: widget.otherHint,
        enabled: !_busy,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        onChanged: _refresh,
      ),
      const SizedBox(height: AleraTokens.space8),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton(
          key: const ValueKey<String>(
            'gateOption:${AleraGateCard.otherOptionId}',
          ),
          onPressed: _locked || answer.isEmpty
              ? null
              : () => widget.onSelected(AleraGateCard.otherOptionId, answer),
          child: Text(
            sending ? widget.sendingOtherLabel : widget.sendOtherLabel,
          ),
        ),
      ),
    ];
  }
}
