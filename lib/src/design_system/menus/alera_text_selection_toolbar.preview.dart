import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/menus/alera_text_selection_toolbar.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Text Selection',
  group: 'Text Selection Toolbar',
  size: Size(280, 220),
)
Widget aleraTextSelectionToolbarPreview() => AleraTextSelectionToolbar(
  anchors: const TextSelectionToolbarAnchors(primaryAnchor: Offset(140, 180)),
  buttonItems: <ContextMenuButtonItem>[
    ContextMenuButtonItem(type: ContextMenuButtonType.cut, onPressed: _noop),
    ContextMenuButtonItem(type: ContextMenuButtonType.copy, onPressed: _noop),
    ContextMenuButtonItem(
      type: ContextMenuButtonType.selectAll,
      onPressed: _noop,
    ),
  ],
);

void _noop() {}
