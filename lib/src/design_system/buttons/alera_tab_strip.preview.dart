import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/buttons/alera_tab_strip.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Run tabs', group: 'Tab strip', size: Size(520, 120))
Widget aleraTabStripPreview() => AleraTabStrip<String>(
  items: const <AleraTabStripItem<String>>[
    AleraTabStripItem<String>(value: 'overview', label: 'Overview'),
    AleraTabStripItem<String>(value: 'tasks', label: 'Tasks', badge: '4/9'),
    AleraTabStripItem<String>(value: 'gates', label: 'Gates', badge: '2'),
    AleraTabStripItem<String>(value: 'timeline', label: 'Timeline', badge: '6'),
  ],
  selected: 'tasks',
  onSelected: (_) {},
);
