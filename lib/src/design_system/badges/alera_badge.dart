import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Semantic tone of an [AleraBadge]. Status tones are for status semantics
/// only; tags and counts stay [neutral].
enum AleraBadgeTone {
  neutral,
  accent,
  attention,
  success,
  error,
  info,
  done;

  /// Text and icon color of the tinted label.
  Color get foreground => switch (this) {
    neutral => AleraTokens.foregroundMuted,
    accent => AleraTokens.foreground,
    attention => AleraTokens.warning,
    success => AleraTokens.success,
    error => AleraTokens.error,
    info => AleraTokens.info,
    done => AleraTokens.done,
  };

  /// Fill behind the label: the tone color at [AleraTokens.statusTintAlpha],
  /// except the grayscale tones, which keep the neutral accent fill.
  Color get background => switch (this) {
    neutral || accent => AleraTokens.accentSubtle,
    _ => foreground.withValues(alpha: AleraTokens.statusTintAlpha),
  };
}

/// Small tinted label used to tag a row (the "Primary" workspace marker, a
/// search match count) or name a status ("Needs Input", "Checks Passing").
///
/// [tone] picks the tinted style; [color]/[foregroundColor] still override the
/// fill and text for callers that need a custom pairing. An optional [icon] or
/// leading [dot] in the text color precedes the label.
class const AleraBadge({
  super.key,
  required final String label,
  final AleraBadgeTone tone = AleraBadgeTone.neutral,
  final Color? color,
  final Color? foregroundColor,
  final IconData? icon,
  final bool dot = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final foreground = foregroundColor ?? tone.foreground;
    final text = Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: .ellipsis,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: foreground, fontWeight: .w600),
    );
    final leading = icon != null
        ? Icon(icon, size: AleraTokens.iconXs, color: foreground)
        : dot
        ? Container(
            width: AleraTokens.statusDotSm,
            height: AleraTokens.statusDotSm,
            decoration: BoxDecoration(color: foreground, shape: .circle),
          )
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space2,
      ),
      decoration: BoxDecoration(
        color: color ?? tone.background,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      ),
      child: leading == null
          ? text
          : Row(
              mainAxisSize: .min,
              children: <Widget>[
                leading,
                const SizedBox(width: AleraTokens.space4),
                Flexible(child: text),
              ],
            ),
    );
  }
}
