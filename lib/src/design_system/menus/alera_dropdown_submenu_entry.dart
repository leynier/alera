import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// [PopupMenuEntry] that opens a nested menu beside itself on tap.
class const AleraDropdownSubmenuEntry<T>({
  super.key,
  required final String label,
  required final List<PopupMenuEntry<T>> items,
  final Widget? leading,
  final bool enabled = true,
}) extends PopupMenuEntry<T> {
  @override
  double get height => 36;

  @override
  bool represents(T? value) => false;

  @override
  State<AleraDropdownSubmenuEntry<T>> createState() =>
      _AleraDropdownSubmenuEntryState<T>();
}

class _AleraDropdownSubmenuEntryState<T>
    extends State<AleraDropdownSubmenuEntry<T>> {
  bool _opening = false;

  Future<void> _openSubmenu() async {
    if (_opening || !widget.enabled || widget.items.isEmpty) {
      return;
    }
    _opening = true;
    try {
      final itemBox = context.findRenderObject()! as RenderBox;
      final overlay = Navigator.of(
        context,
      ).overlay!.context.findRenderObject()! as RenderBox;
      final topLeft = itemBox.localToGlobal(Offset.zero, ancestor: overlay);
      final selected = await showMenu<T>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(
            topLeft.dx + itemBox.size.width,
            topLeft.dy,
            0,
            itemBox.size.height,
          ),
          Offset.zero & overlay.size,
        ),
        items: widget.items,
      );
      if (selected != null && mounted) {
        Navigator.of(context).pop(selected);
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? AleraTokens.foreground
        : AleraTokens.foregroundFaint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        onTap: widget.enabled ? _openSubmenu : null,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        borderRadius: .circular(AleraTokens.radiusLg),
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
              Icon(AleraIcons.chevronRight, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
