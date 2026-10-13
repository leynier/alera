import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// [PopupMenuEntry] styled for Alera popovers: tokenized radius/padding, a
/// trailing check for the [selected] value, optional leading content, an
/// optional muted [detail] beside the label, and pop-on-tap semantics.
class const AleraDropdownEntry<T>({
  super.key,
  required final T value,
  required final String label,
  final Widget? leading,
  final String? detail,
  final bool selected = false,
  final bool enabled = true,
}) extends PopupMenuEntry<T> {
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
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        borderRadius: .circular(AleraTokens.radiusSm),
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
              if (widget.detail case final detail?) ...<Widget>[
                const SizedBox(width: AleraTokens.space12),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AleraTokens.foregroundMuted),
                ),
              ],
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

/// Non-interactive group title inside an Alera popover menu.
class const AleraDropdownGroupHeader<T>({
  super.key,
  required final String label,
}) extends PopupMenuEntry<T> {
  @override
  double get height => 28;

  @override
  bool represents(T? value) => false;

  @override
  State<AleraDropdownGroupHeader<T>> createState() =>
      _AleraDropdownGroupHeaderState<T>();
}

class _AleraDropdownGroupHeaderState<T>
    extends State<AleraDropdownGroupHeader<T>> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AleraTokens.space8,
      AleraTokens.space8,
      AleraTokens.space8,
      AleraTokens.space4,
    ),
    child: Text(
      widget.label,
      maxLines: 1,
      overflow: .ellipsis,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AleraTokens.foregroundMuted),
    ),
  );
}
