import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:flutter/material.dart';

/// One selectable option of an [AleraDropdownField].
class AleraDropdownFieldEntry<T> {
  const AleraDropdownFieldEntry({
    required this.value,
    required this.label,
    this.leading,
    this.enabled = true,
  });

  final T value;
  final String label;
  final Widget? leading;
  final bool enabled;
}

/// Tokenized select field: a text-field-like trigger that opens an Alera
/// popover menu of [AleraDropdownFieldEntry] options and reports the picked
/// value through [onChanged].
class AleraDropdownField<T> extends StatelessWidget {
  const AleraDropdownField({
    super.key,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.hintText,
    this.enabled = true,
  });

  final T? value;
  final List<AleraDropdownFieldEntry<T>> entries;
  final ValueChanged<T> onChanged;
  final String? hintText;
  final bool enabled;

  static const double _height = 34;

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final selected = await showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height + AleraTokens.space4,
        overlay.size.width - origin.dx - box.size.width,
        overlay.size.height - origin.dy,
      ),
      constraints: BoxConstraints(minWidth: box.size.width),
      color: AleraTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        side: const BorderSide(color: AleraTokens.border),
      ),
      items: <PopupMenuEntry<T>>[
        for (final entry in entries)
          AleraDropdownEntry<T>(
            value: entry.value,
            label: entry.label,
            leading: entry.leading,
            selected: entry.value == value,
            enabled: entry.enabled,
          ),
      ],
    );
    if (selected != null && selected != value) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    AleraDropdownFieldEntry<T>? current;
    for (final entry in entries) {
      if (entry.value == value) {
        current = entry;
        break;
      }
    }
    final labelColor = !enabled
        ? AleraTokens.foregroundFaint
        : current == null
        ? AleraTokens.foregroundMuted
        : AleraTokens.foreground;
    return Semantics(
      button: true,
      enabled: enabled,
      label: current?.label ?? hintText,
      child: InkWell(
        onTap: enabled ? () => _openMenu(context) : null,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Container(
          height: _height,
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
          decoration: BoxDecoration(
            color: AleraTokens.surfaceVariant,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.border),
          ),
          child: Row(
            children: <Widget>[
              if (current?.leading != null) ...<Widget>[
                current!.leading!,
                const SizedBox(width: AleraTokens.space8),
              ],
              Expanded(
                child: Text(
                  current?.label ?? hintText ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: labelColor,
                  ),
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              Icon(
                AleraIcons.chevronDown,
                size: 16,
                color: enabled
                    ? AleraTokens.foregroundMuted
                    : AleraTokens.foregroundFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
