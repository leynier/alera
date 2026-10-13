import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_filter_popover.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:flutter/material.dart';

/// One selectable option of an [AleraDropdownField]. Consecutive entries
/// with the same [group] sit under one header; [detail] is a muted note shown
/// beside the label in the menu.
class const AleraDropdownFieldEntry<T>({
  required final T value,
  required final String label,
  final Widget? leading,
  final bool enabled = true,
  final String? group,
  final String? detail,
});

/// Inserts a group header before each run of entries that starts a new group.
List<PopupMenuEntry<V>> _withGroupHeaders<T, V>(
  List<AleraDropdownFieldEntry<T>> entries,
  PopupMenuEntry<V> Function(int index, AleraDropdownFieldEntry<T> entry) item,
) {
  final items = <PopupMenuEntry<V>>[];
  String? group;
  for (final (index, entry) in entries.indexed) {
    if (entry.group != null && entry.group != group) {
      items.add(AleraDropdownGroupHeader<V>(label: entry.group!));
    }
    group = entry.group;
    items.add(item(index, entry));
  }
  return items;
}

/// Tokenized select field: a text-field-like trigger that opens an Alera
/// popover menu of [AleraDropdownFieldEntry] options and reports the picked
/// value through [onChanged]. When [filterable], the popover carries a search
/// field that narrows the options as the user types.
class const AleraDropdownField<T>({
  super.key,
  required final T? value,
  required final List<AleraDropdownFieldEntry<T>> entries,
  required final ValueChanged<T> onChanged,
  final String? hintText,
  final String? labelText,
  final bool enabled = true,
  final bool filterable = false,
  final String filterHintText = 'Search',
}) extends StatefulWidget {
  static const double _height = AleraTokens.controlHeight;

  @override
  State<AleraDropdownField<T>> createState() => _AleraDropdownFieldState<T>();
}

class _AleraDropdownFieldState<T> extends State<AleraDropdownField<T>> {
  final AleraPopoverController _filterPopover = AleraPopoverController();

  @override
  void initState() {
    super.initState();
    _filterPopover.addListener(_handleFilterPopoverChanged);
  }

  @override
  void dispose() {
    _filterPopover.dispose();
    super.dispose();
  }

  void _handleFilterPopoverChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + box.size.height + AleraTokens.space4,
      overlay.size.width - origin.dx - box.size.width,
      overlay.size.height - origin.dy,
    );
    final constraints = BoxConstraints(minWidth: box.size.width);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      side: const BorderSide(color: AleraTokens.border),
    );
    final entries = widget.entries;
    if (entries.any((entry) => entry.value == null)) {
      // A null-valued entry (e.g. "No Parent") is indistinguishable from a
      // dismissed menu when popped as a value, so resolve by entry index.
      final selectedIndex = await showMenu<int>(
        context: context,
        position: position,
        constraints: constraints,
        color: AleraTokens.surface,
        shape: shape,
        items: _withGroupHeaders<T, int>(
          entries,
          (index, entry) => AleraDropdownEntry<int>(
            value: index,
            label: entry.label,
            leading: entry.leading,
            detail: entry.detail,
            selected: entry.value == widget.value,
            enabled: entry.enabled,
          ),
        ),
      );
      if (selectedIndex == null) {
        return;
      }
      final selected = entries[selectedIndex].value;
      if (selected != widget.value) {
        widget.onChanged(selected);
      }
      return;
    }
    final selected = await showMenu<T>(
      context: context,
      position: position,
      constraints: constraints,
      color: AleraTokens.surface,
      shape: shape,
      items: _withGroupHeaders<T, T>(
        entries,
        (_, entry) => AleraDropdownEntry<T>(
          value: entry.value,
          label: entry.label,
          leading: entry.leading,
          detail: entry.detail,
          selected: entry.value == widget.value,
          enabled: entry.enabled,
        ),
      ),
    );
    if (selected != null && selected != widget.value) {
      widget.onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    AleraDropdownFieldEntry<T>? current;
    for (final entry in widget.entries) {
      if (entry.value == widget.value) {
        current = entry;
        break;
      }
    }
    final labelColor = !widget.enabled
        ? AleraTokens.foregroundFaint
        : current == null
        ? AleraTokens.foregroundMuted
        : AleraTokens.foreground;
    final open = _filterPopover.isOpen;
    final field = Semantics(
      button: true,
      enabled: widget.enabled,
      label: current?.label ?? widget.hintText,
      child: InkWell(
        onTap: widget.enabled
            ? () => widget.filterable
                  ? _filterPopover.toggle()
                  : _openMenu(context)
            : null,
        borderRadius: .circular(AleraTokens.radiusMd),
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Container(
          height: AleraDropdownField._height,
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
                  current?.label ?? widget.hintText ?? '',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: labelColor,
                  ),
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              Icon(
                open ? AleraIcons.chevronUp : AleraIcons.chevronDown,
                size: 16,
                color: widget.enabled
                    ? AleraTokens.foregroundMuted
                    : AleraTokens.foregroundFaint,
              ),
            ],
          ),
        ),
      ),
    );
    final anchored = !widget.filterable
        ? field
        : AleraPopover(
            controller: _filterPopover,
            matchAnchorWidth: true,
            toggleOnAnchorTap: false,
            builder: (context, close) => AleraDropdownFilterPopover<T>(
              entries: List<AleraDropdownFieldEntry<T>>.of(widget.entries),
              selectedValue: widget.value,
              filterHintText: widget.filterHintText,
              onDismiss: close,
              onSelected: (value) {
                close();
                if (value != widget.value) {
                  widget.onChanged(value);
                }
              },
            ),
            child: field,
          );
    final label = widget.labelText;
    if (label == null) {
      return anchored;
    }
    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space4),
        anchored,
      ],
    );
  }
}
