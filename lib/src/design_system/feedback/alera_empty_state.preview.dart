import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Message only', group: 'Empty state')
Widget aleraEmptyStatePreview() =>
    const AleraEmptyState(message: 'No settings found.');

@AleraPreview(name: 'With icon', group: 'Empty state')
Widget aleraEmptyStateIconPreview() => const AleraEmptyState(
  icon: AleraIcons.searchOff,
  title: 'No matching results',
  message: 'Adjust the filters and try again.',
);
