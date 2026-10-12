import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Formats a time of day the way [AleraTimeOfDayField] displays it: "09:30".
String formatAleraTimeOfDay(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// A field-shaped button that shows [text] with a leading [icon] and opens a
/// picker on tap. [placeholder] dims the text while nothing is chosen. Used by
/// the phone time and date fields, where a picker is easier than typing.
class const AleraPickerFieldButton({
  super.key,
  required final String text,
  required final IconData icon,
  required final VoidCallback? onTap,
  final String? semanticsLabel,
  final bool placeholder = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final foreground = !enabled
        ? AleraTokens.foregroundFaint
        : placeholder
        ? AleraTokens.foregroundMuted
        : AleraTokens.foreground;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: .circular(AleraTokens.radiusMd),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AleraTokens.buttonMinHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
          decoration: BoxDecoration(
            color: AleraTokens.surfaceVariant,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.border),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: AleraTokens.rowMetaIcon, color: foreground),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A label above field content, in the style of the phone dropdown field.
class const AleraLabeledField({
  super.key,
  required final Widget child,
  final String? labelText,
  final String? errorText,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = labelText;
    final error = errorText;
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
        ],
        child,
        if (error != null && error.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// Time-of-day entry for a phone: shows "09:30" and opens the system time
/// picker on tap, so [onChanged] only ever sees a real time.
///
/// Phone counterpart of the desktop `AleraTimeOfDayField`, which is typed.
class const AleraTimeOfDayField({
  super.key,
  required final int hour,
  required final int minute,
  required final void Function(int hour, int minute) onChanged,
  final String? labelText,
  final bool enabled = true,
}) extends StatelessWidget {
  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (picked == null) return;
    if (picked.hour != hour || picked.minute != minute) {
      onChanged(picked.hour, picked.minute);
    }
  }

  @override
  Widget build(BuildContext context) => AleraLabeledField(
    labelText: labelText,
    child: AleraPickerFieldButton(
      text: formatAleraTimeOfDay(hour, minute),
      icon: AleraIcons.time,
      semanticsLabel: labelText,
      onTap: enabled ? () => _pick(context) : null,
    ),
  );
}
