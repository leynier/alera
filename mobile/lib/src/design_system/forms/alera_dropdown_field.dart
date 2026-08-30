import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:flutter/material.dart';

/// One selectable option of an [AleraDropdownField].
class const AleraDropdownFieldEntry<T>({
  required final T value,
  required final String label,
  final Widget? leading,
  final bool enabled = true,
});

/// Tokenized select field: a text-field-like trigger that opens an Alera
/// popover menu of [AleraDropdownFieldEntry] options and reports the picked
/// value through [onChanged].
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
}) extends StatelessWidget {
  static const double _height = 34;

  Future<void> _openMenu(BuildContext context) async {
    if (filterable) {
      final selectedIndex = await showDialog<int>(
        context: context,
        builder: (_) => _AleraDropdownSearchDialog<T>(
          title: labelText,
          hintText: filterHintText,
          entries: entries,
          selectedValue: value,
        ),
      );
      if (selectedIndex == null) {
        return;
      }
      final selected = entries[selectedIndex].value;
      if (selected != value) {
        onChanged(selected);
      }
      return;
    }
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
    if (entries.any((entry) => entry.value == null)) {
      // A null-valued entry is indistinguishable from a dismissed menu when
      // popped as a value, so resolve by entry index.
      final selectedIndex = await showMenu<int>(
        context: context,
        position: position,
        constraints: constraints,
        color: AleraTokens.surface,
        shape: shape,
        items: <PopupMenuEntry<int>>[
          for (final (index, entry) in entries.indexed)
            AleraDropdownEntry<int>(
              value: index,
              label: entry.label,
              leading: entry.leading,
              selected: entry.value == value,
              enabled: entry.enabled,
            ),
        ],
      );
      if (selectedIndex == null) {
        return;
      }
      final selected = entries[selectedIndex].value;
      if (selected != value) {
        onChanged(selected);
      }
      return;
    }
    final selected = await showMenu<T>(
      context: context,
      position: position,
      constraints: constraints,
      color: AleraTokens.surface,
      shape: shape,
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
    final field = Semantics(
      button: true,
      enabled: enabled,
      label: current?.label ?? hintText,
      child: InkWell(
        onTap: enabled ? () => _openMenu(context) : null,
        borderRadius: .circular(AleraTokens.radiusMd),
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
                  overflow: .ellipsis,
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
    final label = labelText;
    if (label == null) {
      return field;
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
        field,
      ],
    );
  }
}

class const _AleraDropdownSearchDialog<T>({
  required final String? title,
  required final String hintText,
  required final List<AleraDropdownFieldEntry<T>> entries,
  required final T? selectedValue,
}) extends StatefulWidget {
  @override
  State<_AleraDropdownSearchDialog<T>> createState() =>
      _AleraDropdownSearchDialogState<T>();
}

class _AleraDropdownSearchDialogState<T>
    extends State<_AleraDropdownSearchDialog<T>> {
  String _query = '';

  List<int> get _visibleIndexes {
    final query = _query.trim().toLowerCase();
    return <int>[
      for (final entry in widget.entries.asMap().entries)
        if (query.isEmpty || entry.value.label.toLowerCase().contains(query))
          entry.key,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final indexes = _visibleIndexes;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 280,
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space16),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Text(
                widget.title ?? 'Select',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AleraTokens.space12),
              AleraSearchField(
                hintText: widget.hintText,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AleraTokens.space8),
              Flexible(
                child: indexes.isEmpty
                    ? const Center(child: Text('No results'))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: indexes.length,
                        itemBuilder: (context, visibleIndex) {
                          final index = indexes[visibleIndex];
                          final entry = widget.entries[index];
                          return ListTile(
                            dense: true,
                            enabled: entry.enabled,
                            selected: entry.value == widget.selectedValue,
                            leading: entry.leading,
                            title: Text(entry.label, overflow: .ellipsis),
                            onTap: entry.enabled
                                ? () => Navigator.of(context).pop(index)
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
