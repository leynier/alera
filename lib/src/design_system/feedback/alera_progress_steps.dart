import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

enum AleraProgressStepState { pending, active, done, failed, skipped }

/// One row of an [AleraProgressSteps] list. [progress] (0..1) draws a bar
/// under the label and only applies while the step is active.
class const AleraProgressStep({
  required final String label,
  final String? detail,
  final AleraProgressStepState state = AleraProgressStepState.pending,
  final double? progress,
});

/// Vertical checklist for multi-step work: a glyph per step joined by a
/// hairline connector, with the active step spinning.
class const AleraProgressSteps({
  super.key,
  required final List<AleraProgressStep> steps,
  final bool dense = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        for (var index = 0; index < steps.length; index++)
          _AleraProgressStepRow(
            step: steps[index],
            dense: dense,
            last: index == steps.length - 1,
          ),
      ],
    );
  }
}

class const _AleraProgressStepRow({
  required final AleraProgressStep step,
  required final bool dense,
  required final bool last,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelBase = dense
        ? theme.textTheme.bodySmall
        : theme.textTheme.bodyMedium;
    final labelStyle = labelBase?.copyWith(
      color: _labelColor(step.state),
      fontWeight: step.state == AleraProgressStepState.active ? .w600 : null,
    );
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: step.state == AleraProgressStepState.failed
          ? AleraTokens.error
          : AleraTokens.foregroundMuted,
    );
    final gap = dense ? AleraTokens.space4 : AleraTokens.space8;
    final progress = step.progress;
    final detail = step.detail?.trim();
    return Semantics(
      label: '${step.label}, ${step.state.name}',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Column(
              children: <Widget>[
                SizedBox.square(
                  dimension: AleraTokens.iconMd,
                  child: _AleraProgressStepGlyph(state: step.state),
                ),
                if (!last)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AleraTokens.space2,
                      ),
                      child: Container(
                        width: AleraTokens.dividerExtent,
                        color: AleraTokens.borderSubtle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : gap),
                child: Column(
                  crossAxisAlignment: .start,
                  mainAxisSize: .min,
                  children: <Widget>[
                    Text(step.label, style: labelStyle),
                    if (detail != null && detail.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AleraTokens.space2),
                      Text(detail, style: detailStyle),
                    ],
                    if (step.state == AleraProgressStepState.active &&
                        progress != null) ...<Widget>[
                      const SizedBox(height: AleraTokens.space4),
                      LinearProgressIndicator(
                        value: progress.clamp(0, 1),
                        color: AleraTokens.accent,
                        backgroundColor: AleraTokens.borderSubtle,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _labelColor(AleraProgressStepState state) {
    return switch (state) {
      AleraProgressStepState.active => AleraTokens.foreground,
      AleraProgressStepState.done => AleraTokens.foregroundMuted,
      AleraProgressStepState.failed => AleraTokens.error,
      AleraProgressStepState.pending ||
      AleraProgressStepState.skipped => AleraTokens.foregroundFaint,
    };
  }
}

class const _AleraProgressStepGlyph({
  required final AleraProgressStepState state,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return switch (state) {
      AleraProgressStepState.active => const Padding(
        padding: EdgeInsets.all(AleraTokens.space2),
        child: CircularProgressIndicator(
          strokeWidth: AleraTokens.strokeSm,
          color: AleraTokens.accent,
        ),
      ),
      AleraProgressStepState.pending => const Icon(
        AleraIcons.circle,
        size: AleraTokens.iconMd,
        color: AleraTokens.foregroundFaint,
      ),
      AleraProgressStepState.done => const Icon(
        AleraIcons.check,
        size: AleraTokens.iconMd,
        color: AleraTokens.foregroundMuted,
      ),
      AleraProgressStepState.failed => const Icon(
        AleraIcons.error,
        size: AleraTokens.iconMd,
        color: AleraTokens.error,
      ),
      AleraProgressStepState.skipped => const Icon(
        AleraIcons.cancel,
        size: AleraTokens.iconMd,
        color: AleraTokens.foregroundFaint,
      ),
    };
  }
}
