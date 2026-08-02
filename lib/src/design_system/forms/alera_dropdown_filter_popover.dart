import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Popover opened by [AleraDropdownField] when filterable: a search field on
/// top and the matching entries below. Entries starting with the query sort
/// before entries that merely contain it. Arrow keys move the highlight,
/// Enter picks the highlighted entry, Escape dismisses.
class AleraDropdownFilterPopover<T> extends StatefulWidget {
  const AleraDropdownFilterPopover({
    super.key,
    required this.entries,
    required this.selectedValue,
    required this.width,
    required this.filterHintText,
    required this.onSelected,
    required this.onDismiss,
  });

  final List<AleraDropdownFieldEntry<T>> entries;
  final T? selectedValue;
  final double width;
  final String filterHintText;
  final ValueChanged<T> onSelected;
  final VoidCallback onDismiss;

  static const double _listMaxHeight = 220;

  @override
  State<AleraDropdownFilterPopover<T>> createState() =>
      _AleraDropdownFilterPopoverState<T>();
}

class _AleraDropdownFilterPopoverState<T>
    extends State<AleraDropdownFilterPopover<T>> {
  final TextEditingController _filterController = TextEditingController();
  final FocusNode _filterFocusNode = FocusNode(
    debugLabel: 'AleraDropdownFilter',
  );
  String _query = '';
  int _highlightedIndex = -1;

  @override
  void initState() {
    super.initState();
    _highlightedIndex = _initialHighlight(_filteredEntries);
    // The popover lives in its own overlay entry, where TextField autofocus
    // does not reliably win against the trigger that just requested focus, so
    // request it explicitly once the entry is attached.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _filterFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _filterFocusNode.unfocus();
    _filterFocusNode.dispose();
    _filterController.dispose();
    super.dispose();
  }

  List<AleraDropdownFieldEntry<T>> get _filteredEntries {
    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return widget.entries;
    }
    return <AleraDropdownFieldEntry<T>>[
      for (final entry in widget.entries)
        if (entry.label.toLowerCase().startsWith(normalized)) entry,
      for (final entry in widget.entries)
        if (!entry.label.toLowerCase().startsWith(normalized) &&
            entry.label.toLowerCase().contains(normalized))
          entry,
    ];
  }

  int _initialHighlight(List<AleraDropdownFieldEntry<T>> entries) {
    for (final (index, entry) in entries.indexed) {
      if (entry.value == widget.selectedValue && entry.enabled) {
        return index;
      }
    }
    return _nextEnabled(entries, -1, 1);
  }

  int _nextEnabled(
    List<AleraDropdownFieldEntry<T>> entries,
    int from,
    int step,
  ) {
    var index = from;
    for (var count = 0; count < entries.length; count++) {
      index += step;
      if (index < 0) {
        index = entries.length - 1;
      } else if (index >= entries.length) {
        index = 0;
      }
      if (entries[index].enabled) {
        return index;
      }
    }
    return -1;
  }

  void _handleQueryChanged(String value) {
    setState(() {
      _query = value;
      final entries = _filteredEntries;
      _highlightedIndex = entries.isEmpty ? -1 : _nextEnabled(entries, -1, 1);
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final entries = _filteredEntries;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (entries.isNotEmpty) {
        setState(
          () => _highlightedIndex = _nextEnabled(entries, _highlightedIndex, 1),
        );
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (entries.isNotEmpty) {
        setState(
          () =>
              _highlightedIndex = _nextEnabled(entries, _highlightedIndex, -1),
        );
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_highlightedIndex >= 0 && _highlightedIndex < entries.length) {
        widget.onSelected(entries[_highlightedIndex].value);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _filteredEntries;
    return Focus(
      onKeyEvent: _handleKey,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: widget.width,
          decoration: BoxDecoration(
            color: AleraTokens.surface,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space8),
                child: AleraTextField(
                  controller: _filterController,
                  focusNode: _filterFocusNode,
                  autofocus: true,
                  dense: true,
                  hintText: widget.filterHintText,
                  prefixIcon: AleraIcons.search,
                  textActionsEnabled: false,
                  onChanged: _handleQueryChanged,
                ),
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: AleraDropdownFilterPopover._listMaxHeight,
                  ),
                  child: entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AleraTokens.space12,
                            vertical: AleraTokens.space12,
                          ),
                          child: Text(
                            'No matching options',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AleraTokens.foregroundFaint,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(
                            left: AleraTokens.space4,
                            right: AleraTokens.space4,
                            bottom: AleraTokens.space4,
                          ),
                          shrinkWrap: true,
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return AleraMenuItem(
                              label: entry.label,
                              leading: entry.leading,
                              enabled: entry.enabled,
                              selected: entry.value == widget.selectedValue,
                              active: index == _highlightedIndex,
                              onHover: entry.enabled
                                  ? () => setState(
                                      () => _highlightedIndex = index,
                                    )
                                  : null,
                              onTap: entry.enabled
                                  ? () => widget.onSelected(entry.value)
                                  : () {},
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
