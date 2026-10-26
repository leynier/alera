import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// The phone's copy of the desktop `AleraInlineChip`; keep the two in sync.
///
/// A token chip that sits inside a run of text, such as a skill a person
/// invoked in a chat message. It is outlined rather than filled so it stays
/// visible on the tinted surfaces messages use, and it shares the line's
/// baseline through [span].
class const AleraInlineChip({
  super.key,
  required final String label,
  final IconData? icon,

  /// What the chip stands for in the text, such as `$review`.
  final String? tooltip,
}) extends StatelessWidget {
  /// The chip as a span for a [Text.rich] or a Markdown run.
  static InlineSpan span({
    required String label,
    IconData? icon,
    String? tooltip,
  }) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: AleraInlineChip(label: label, icon: icon, tooltip: tooltip),
  );

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: AleraTokens.foreground, fontWeight: .w500);
    final chip = Container(
      margin: const EdgeInsets.symmetric(horizontal: AleraTokens.space2),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space2,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        border: Border.all(color: AleraTokens.border),
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: .min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(
              icon,
              size: AleraTokens.iconSm,
              color: AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space4),
          ],
          Flexible(
            child: Text(label, maxLines: 1, overflow: .ellipsis, style: style),
          ),
        ],
      ),
    );
    final message = tooltip;
    return Semantics(
      label: message == null ? label : '$label, $message',
      excludeSemantics: true,
      child: message == null ? chip : Tooltip(message: message, child: chip),
    );
  }
}
