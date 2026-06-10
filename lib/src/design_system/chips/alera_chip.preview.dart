import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Tag', group: 'Chip')
Widget aleraChipTagPreview() => const AleraChip(label: 'Alera');

@AleraPreview(name: 'Removable', group: 'Chip')
Widget aleraChipRemovablePreview() =>
    AleraChip(label: 'Alera', onRemove: () {});
