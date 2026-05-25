import 'package:alera/src/app/theme/alera_tokens.dart';
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
  });

  final T value;
  final String label;
  final Widget? leading;
  final bool selected;

  @override
  double get height => 36;

  @override
  bool represents(T? value) => this.value == value;

  @override
  State<AleraDropdownEntry<T>> createState() => _AleraDropdownEntryState<T>();
}

class _AleraDropdownEntryState<T> extends State<AleraDropdownEntry<T>> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        autofocus: widget.selected,
        onTap: () => Navigator.of(context).pop(widget.value),
        mouseCursor: SystemMouseCursors.click,
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
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (widget.selected)
                const Icon(
                  Icons.check,
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
