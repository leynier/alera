import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// [PopupMenuEntry] styled for Alera popovers: tokenized radius/padding, a
/// trailing check for the [selected] value, optional leading content, and
/// pop-on-tap semantics.
class AleraDropdownEntry<T> extends PopupMenuEntry<T> {
  const AleraDropdownEntry({
    super.key,
    required this.value,
    required this.label,
    this.leading,
    this.selected = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final Widget? leading;
  final bool selected;
  final bool enabled;

  @override
  double get height => 36;

  @override
  bool represents(T? value) => enabled && this.value == value;

  @override
  State<AleraDropdownEntry<T>> createState() => _AleraDropdownEntryState<T>();
}

class _AleraDropdownEntryState<T> extends State<AleraDropdownEntry<T>> {
  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? AleraTokens.foreground
        : AleraTokens.foregroundFaint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        autofocus: widget.selected,
        onTap: widget.enabled
            ? () => Navigator.of(context).pop(widget.value)
            : null,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
          ),
          child: Row(
            children: <Widget>[
              if (widget.leading != null) ...<Widget>[
                widget.leading!,
                const SizedBox(width: AleraTokens.space8),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: color),
                ),
              ),
              if (widget.selected)
                const Icon(
                  AleraIcons.check,
                  size: 16,
                  color: AleraTokens.foreground,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
