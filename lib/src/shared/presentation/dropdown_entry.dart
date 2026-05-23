import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

class DropdownEntry<T> extends PopupMenuEntry<T> {
  const DropdownEntry({
    super.key,
    required this.value,
    required this.label,
    this.selected = false,
  });

  final T value;
  final String label;
  final bool selected;

  @override
  double get height => 36;

  @override
  bool represents(T? value) => this.value == value;

  @override
  State<DropdownEntry<T>> createState() => _DropdownEntryState<T>();
}

class _DropdownEntryState<T> extends State<DropdownEntry<T>> {
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
