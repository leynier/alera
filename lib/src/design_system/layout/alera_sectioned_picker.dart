import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One choice of an [AleraSectionedPicker]. A non-empty [disabledReason]
/// disables the row and is shown in place of [subtitle]. [keywords] are
/// searched like the title without being shown, such as the name of the
/// section a row belongs to.
class const AleraPickerRow<T>({
  required final T value,
  required final String title,
  final String? subtitle,
  final Widget? leading,
  final String? disabledReason,
  final List<String> keywords = const <String>[],
}) {
  bool get enabled => disabledReason == null || disabledReason!.isEmpty;

  bool matches(String query) =>
      title.toLowerCase().contains(query) ||
      (subtitle?.toLowerCase().contains(query) ?? false) ||
      keywords.any((keyword) => keyword.toLowerCase().contains(query));
}

/// Titled group of [AleraPickerRow]s. [emptyMessage], when set, is shown
/// under the title while the section has no rows and no search is active;
/// otherwise an empty section is hidden.
class const AleraPickerSection<T>({
  required final String title,
  required final List<AleraPickerRow<T>> rows,
  final String? emptyMessage,
});

/// Searchable list of titled sections, for choosing one value from several
/// kinds of targets inside an `AleraPopover` or a dialog.
///
/// Typing filters rows by title and subtitle. Arrow keys move the highlight
/// across sections and skip disabled rows, Enter picks the highlighted row,
/// and the row matching [selectedValue] carries the [AleraActiveRail] and is
/// scrolled into view when the picker opens.
class const AleraSectionedPicker<T>({
  super.key,
  required final List<AleraPickerSection<T>> sections,
  required final ValueChanged<T> onSelected,
  final T? selectedValue,
  final bool searchable = true,
  final String searchHintText = 'Search',
  final String emptyMessage = 'No matches.',
  final bool autofocus = true,
  final double maxListHeight = AleraTokens.dialogMaxHeight,
}) extends StatefulWidget {
  @override
  State<AleraSectionedPicker<T>> createState() =>
      _AleraSectionedPickerState<T>();
}

class _AleraSectionedPickerState<T> extends State<AleraSectionedPicker<T>> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'AleraSectionedPicker');
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};
  int _highlighted = -1;

  String get _normalizedQuery => _query.text.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    final rows = _visibleRows();
    _highlighted = _initialHighlight(rows);
    final selected = rows.indexWhere(
      (row) => row.value == widget.selectedValue,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // Inside a popover the overlay is attached a frame after the anchor
      // asked for it, so autofocus alone loses to the popover's own scope.
      if (widget.autofocus) {
        _focusNode.requestFocus();
      }
      _revealRow(selected);
    });
  }

  @override
  void didUpdateWidget(AleraSectionedPicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rows = _visibleRows();
    if (_highlighted >= rows.length ||
        (_highlighted >= 0 && !rows[_highlighted].enabled)) {
      _highlighted = _nextEnabled(rows, -1, 1);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scroll.dispose();
    _query.dispose();
    super.dispose();
  }

  List<AleraPickerSection<T>> _visibleSections() {
    final query = _normalizedQuery;
    return <AleraPickerSection<T>>[
      for (final section in widget.sections)
        if (query.isEmpty)
          section
        else
          AleraPickerSection<T>(
            title: section.title,
            rows: <AleraPickerRow<T>>[
              for (final row in section.rows)
                if (row.matches(query)) row,
            ],
          ),
    ];
  }

  List<AleraPickerRow<T>> _visibleRows() => <AleraPickerRow<T>>[
    for (final section in _visibleSections()) ...section.rows,
  ];

  int _initialHighlight(List<AleraPickerRow<T>> rows) {
    for (final (index, row) in rows.indexed) {
      if (row.enabled && row.value == widget.selectedValue) {
        return index;
      }
    }
    return _nextEnabled(rows, -1, 1);
  }

  int _nextEnabled(List<AleraPickerRow<T>> rows, int from, int step) {
    var index = from;
    for (var count = 0; count < rows.length; count++) {
      index = (index + step) % rows.length;
      if (index < 0) {
        index += rows.length;
      }
      if (rows[index].enabled) {
        return index;
      }
    }
    return -1;
  }

  void _handleQueryChanged(String _) {
    setState(() => _highlighted = _nextEnabled(_visibleRows(), -1, 1));
  }

  void _moveHighlight(int step) {
    final rows = _visibleRows();
    if (rows.isEmpty) {
      return;
    }
    setState(() => _highlighted = _nextEnabled(rows, _highlighted, step));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealRow(_highlighted),
    );
  }

  /// Scrolls the row at [index] into view, moving the list only when the
  /// row is not already fully visible.
  void _revealRow(int index, {bool jumped = false}) {
    if (!mounted || index < 0) {
      return;
    }
    final rowContext = _rowKeys[index]?.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        rowContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      return;
    }
    // The list builds rows lazily, so a row far below the fold has no
    // context yet: jump to its share of the list, then align it.
    if (jumped || !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final last = math.max(1, _visibleRows().length - 1);
    position.jumpTo(position.maxScrollExtent * index / last);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealRow(index, jumped: true),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final rows = _visibleRows();
      if (_highlighted >= 0 && _highlighted < rows.length) {
        widget.onSelected(rows[_highlighted].value);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = _visibleSections();
    final filtering = _normalizedQuery.isNotEmpty;
    final children = <Widget>[];
    var rowIndex = 0;
    for (final section in sections) {
      final emptyMessage = section.emptyMessage;
      if (section.rows.isEmpty && (filtering || emptyMessage == null)) {
        continue;
      }
      children.add(
        AleraSectionHeader(
          label: section.title,
          padding: EdgeInsets.only(
            left: AleraTokens.space8,
            right: AleraTokens.space8,
            top: children.isEmpty ? AleraTokens.space4 : AleraTokens.space12,
            bottom: AleraTokens.space4,
          ),
        ),
      );
      if (section.rows.isEmpty) {
        children.add(_PickerMessage(message: emptyMessage!, theme: theme));
      }
      for (final row in section.rows) {
        final index = rowIndex++;
        children.add(
          _PickerRowTile<T>(
            key: _rowKeys.putIfAbsent(index, GlobalKey.new),
            row: row,
            selected: row.value == widget.selectedValue,
            highlighted: index == _highlighted,
            onHover: row.enabled
                ? () => setState(() => _highlighted = index)
                : null,
            onTap: () => widget.onSelected(row.value),
          ),
        );
      }
    }
    return Focus(
      focusNode: widget.searchable ? null : _focusNode,
      onKeyEvent: _handleKey,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          if (widget.searchable)
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space8),
              child: AleraTextField(
                controller: _query,
                focusNode: _focusNode,
                dense: true,
                hintText: widget.searchHintText,
                prefixIcon: AleraIcons.search,
                textActionsEnabled: false,
                onChanged: _handleQueryChanged,
              ),
            ),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxListHeight),
              child: children.isEmpty
                  ? _PickerMessage(message: widget.emptyMessage, theme: theme)
                  : ListView(
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(
                        left: AleraTokens.space4,
                        right: AleraTokens.space4,
                        bottom: AleraTokens.space4,
                      ),
                      children: children,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class const _PickerMessage({
  required final String message,
  required final ThemeData theme,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      ),
    );
  }
}

class const _PickerRowTile<T>({
  super.key,
  required final AleraPickerRow<T> row,
  required final bool selected,
  required final bool highlighted,
  required final VoidCallback? onHover,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = row.enabled;
    final subtitle = enabled ? row.subtitle : row.disabledReason;
    final background = selected || (highlighted && enabled)
        ? AleraActiveRail.selectedColor
        : Colors.transparent;
    return MouseRegion(
      onEnter: onHover == null ? null : (_) => onHover!(),
      child: AleraActiveRail(
        active: selected,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          child: InkWell(
            onTap: enabled ? onTap : null,
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            mouseCursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
                vertical: AleraTokens.space6,
              ),
              child: Row(
                children: <Widget>[
                  if (row.leading case final leading?) ...<Widget>[
                    Opacity(
                      opacity: enabled ? 1 : AleraTokens.disabledOpacity,
                      child: leading,
                    ),
                    const SizedBox(width: AleraTokens.space8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: <Widget>[
                        Text(
                          row.title,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: enabled
                                ? AleraTokens.foreground
                                : AleraTokens.foregroundFaint,
                            fontWeight: selected ? .w600 : .w400,
                          ),
                        ),
                        if (subtitle case final text? when text.isNotEmpty)
                          Text(
                            text,
                            maxLines: 2,
                            overflow: .ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AleraTokens.foregroundMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
