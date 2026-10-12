import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_rail.dart';
import 'package:flutter/material.dart';

const List<AleraRailItem> _items = <AleraRailItem>[
  AleraRailItem(
    icon: AleraIcons.workspaceChildren,
    label: 'Runs',
    count: 3,
    tone: .attention,
  ),
  AleraRailItem(icon: AleraIcons.inbox, label: 'Questions', count: 2),
  AleraRailItem(icon: AleraIcons.checks, label: 'Automations'),
];

@AleraPreview(name: 'Labels', group: 'Rail', size: Size(160, 280))
Widget aleraRailPreview() =>
    AleraRail(items: _items, selectedIndex: 0, onSelected: (_) {});

@AleraPreview(name: 'Compact', group: 'Rail', size: Size(120, 240))
Widget aleraRailCompactPreview() => AleraRail(
  items: _items,
  selectedIndex: 1,
  compact: true,
  onSelected: (_) {},
);
