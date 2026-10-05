import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Message only', group: 'Empty State')
Widget aleraEmptyStatePreview() =>
    const AleraEmptyState(message: 'No settings found.');

@AleraPreview(name: 'With icon', group: 'Empty State')
Widget aleraEmptyStateIconPreview() => const AleraEmptyState(
  icon: AleraIcons.searchOff,
  title: 'No matching results',
  message: 'Adjust the filters and try again.',
);

@AleraPreview(name: 'Loading', group: 'Empty State')
Widget aleraEmptyStateLoadingPreview() =>
    const AleraEmptyState(loading: true, message: 'Loading workspace files…');

@AleraPreview(name: 'With action', group: 'Empty State')
Widget aleraEmptyStateActionPreview() => AleraEmptyState(
  icon: AleraIcons.tabUnselected,
  title: 'Panel is empty',
  message: 'Open a tool or a terminal to get started.',
  action: FilledButton(onPressed: () {}, child: const Text('New Terminal')),
);
