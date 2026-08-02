import 'dart:async';

import 'package:flutter/material.dart';

typedef AleraTextActionsContextMenuHandler =
    void Function(BuildContext context, EditableTextState editableTextState);

/// Adds the optional Text Actions entry without taking ownership of editing.
class AleraTextActionsScope extends InheritedWidget {
  const AleraTextActionsScope({
    super.key,
    required this.enabled,
    required this.onOpen,
    required super.child,
  });

  final bool enabled;
  final AleraTextActionsContextMenuHandler onOpen;

  static AleraTextActionsScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AleraTextActionsScope>();
  }

  static Widget buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState, {
    Future<bool> Function()? onPaste,
    bool textActionsEnabled = true,
  }) {
    final items = List<ContextMenuButtonItem>.from(
      editableTextState.contextMenuButtonItems,
    );
    if (onPaste != null) {
      final pasteItem = ContextMenuButtonItem(
        onPressed: () {
          unawaited(_pasteFromContextMenu(editableTextState, onPaste));
        },
        type: ContextMenuButtonType.paste,
      );
      final pasteIndex = items.indexWhere(
        (item) => item.type == ContextMenuButtonType.paste,
      );
      if (pasteIndex >= 0) {
        items[pasteIndex] = pasteItem;
      } else {
        final selectAllIndex = items.indexWhere(
          (item) => item.type == ContextMenuButtonType.selectAll,
        );
        items.insert(
          selectAllIndex >= 0 ? selectAllIndex : items.length,
          pasteItem,
        );
      }
    }
    final scope = maybeOf(context);
    final selection = editableTextState.textEditingValue.selection;
    final inputType = editableTextState.widget.keyboardType;
    final numericInput =
        inputType.index == TextInputType.number.index ||
        inputType.index == TextInputType.phone.index ||
        inputType.index == TextInputType.datetime.index;
    if (textActionsEnabled &&
        scope?.enabled == true &&
        !editableTextState.widget.readOnly &&
        !editableTextState.widget.obscureText &&
        !numericInput &&
        selection.isValid &&
        !selection.isCollapsed &&
        selection.start >= 0 &&
        selection.end <= editableTextState.textEditingValue.text.length &&
        editableTextState.textEditingValue.text
            .substring(selection.start, selection.end)
            .isNotEmpty) {
      items.add(
        ContextMenuButtonItem(
          label: 'Text Actions',
          onPressed: () => scope!.onOpen(context, editableTextState),
          type: ContextMenuButtonType.custom,
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  static Future<void> _pasteFromContextMenu(
    EditableTextState editableTextState,
    Future<bool> Function() onPaste,
  ) async {
    if (await onPaste()) {
      return;
    }
    await editableTextState.pasteText(SelectionChangedCause.toolbar);
  }

  @override
  bool updateShouldNotify(AleraTextActionsScope oldWidget) {
    return enabled != oldWidget.enabled || onOpen != oldWidget.onOpen;
  }
}
