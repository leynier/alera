import 'dart:async';

import 'package:alera/src/design_system/menus/alera_text_selection_toolbar.dart';
import 'package:flutter/material.dart';

typedef AleraTextActionsContextMenuHandler = void Function(
  BuildContext context,
  AleraTextActionTarget target,
  Offset globalAnchor,
);

typedef AleraTextActionHandler = void Function(
  AleraTextActionTarget target,
  String actionId,
);

typedef AleraTextActionReplacementHandler = bool Function(
  TextEditingValue captured,
  String replacement,
);

class AleraTextActionTarget {
  /// Adapts any editable surface to the shared Text Actions runner.
  const AleraTextActionTarget({
    required this.identity,
    required this.readValue,
    required this.isAvailable,
    required this.applyReplacement,
  });

  final Object identity;
  final TextEditingValue Function() readValue;
  final bool Function() isAvailable;
  final AleraTextActionReplacementHandler applyReplacement;
}

class AleraTextActionMenuItem {
  const AleraTextActionMenuItem({required this.id, required this.label});

  final String id;
  final String label;
}

/// Adds the optional Text Actions entry without taking ownership of editing.
class AleraTextActionsScope extends InheritedWidget {
  const AleraTextActionsScope({
    super.key,
    required this.enabled,
    required this.onOpen,
    this.actions = const <AleraTextActionMenuItem>[],
    this.onRun,
    required super.child,
  });

  final bool enabled;
  final AleraTextActionsContextMenuHandler onOpen;
  final List<AleraTextActionMenuItem> actions;
  final AleraTextActionHandler? onRun;

  void open(
    BuildContext context,
    AleraTextActionTarget target,
    Offset globalAnchor,
  ) {
    if (enabled) {
      onOpen(context, target, globalAnchor);
    }
  }

  void run(EditableTextState editableTextState, String actionId) {
    runTarget(_editableTextTarget(editableTextState), actionId);
  }

  void runTarget(AleraTextActionTarget target, String actionId) {
    if (enabled) {
      onRun?.call(target, actionId);
    }
  }

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
          onPressed: () {
            ContextMenuController.removeAny();
            final anchors = editableTextState.contextMenuAnchors;
            scope!.open(
              context,
              _editableTextTarget(editableTextState),
              anchors.secondaryAnchor ?? anchors.primaryAnchor,
            );
          },
          type: ContextMenuButtonType.custom,
        ),
      );
    }
    return AleraTextSelectionToolbar(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  static AleraTextActionTarget _editableTextTarget(
    EditableTextState editableTextState,
  ) {
    return AleraTextActionTarget(
      identity: editableTextState,
      readValue: () => editableTextState.textEditingValue,
      isAvailable: () => editableTextState.mounted,
      applyReplacement: (captured, replacement) {
        final editingContext = editableTextState.widget.focusNode.context;
        if (editingContext == null || !editingContext.mounted) {
          return false;
        }
        Actions.invoke(
          editingContext,
          ReplaceTextIntent(
            captured,
            replacement,
            captured.selection,
            SelectionChangedCause.toolbar,
          ),
        );
        return true;
      },
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
    return enabled != oldWidget.enabled ||
        onOpen != oldWidget.onOpen ||
        actions != oldWidget.actions ||
        onRun != oldWidget.onRun;
  }
}
