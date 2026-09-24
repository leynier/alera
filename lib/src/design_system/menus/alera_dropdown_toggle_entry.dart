import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:flutter/material.dart';

/// [PopupMenuEntry] with a checkbox that toggles in place.
///
/// Unlike [AleraDropdownEntry] it never closes the menu, so several options
/// can be adjusted before picking an action from the same popover. It keeps
/// its own checked state because a menu route does not rebuild when the
/// caller's data changes.
class const AleraDropdownToggleEntry<T>({
  super.key,
  required final String label,
  required final bool checked,
  required final ValueChanged<bool> onChanged,
  final bool enabled = true,
}) extends PopupMenuEntry<T> {
  @override
  double get height => 36;

  @override
  bool represents(T? value) => false;

  @override
  State<AleraDropdownToggleEntry<T>> createState() =>
      _AleraDropdownToggleEntryState<T>();
}

class _AleraDropdownToggleEntryState<T>
    extends State<AleraDropdownToggleEntry<T>> {
  late bool _checked = widget.checked;

  @override
  void didUpdateWidget(covariant AleraDropdownToggleEntry<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checked != widget.checked) {
      _checked = widget.checked;
    }
  }

  void _toggle([bool? value]) {
    final next = value ?? !_checked;
    setState(() => _checked = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? AleraTokens.foreground
        : AleraTokens.foregroundFaint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        onTap: widget.enabled ? _toggle : null,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        borderRadius: .circular(AleraTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space4,
            vertical: AleraTokens.space2,
          ),
          child: Row(
            children: <Widget>[
              AleraCheckbox(
                value: _checked,
                enabled: widget.enabled,
                onChanged: _toggle,
              ),
              const SizedBox(width: AleraTokens.space4),
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
