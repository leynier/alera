import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Tag', group: 'Chip')
Widget aleraChipTagPreview() => const AleraChip(label: 'Alera');

@AleraPreview(name: 'With Leading Icon', group: 'Chip')
Widget aleraChipLeadingPreview() =>
    const AleraChip(label: 'remote-mac', leading: AleraIcons.host);

@AleraPreview(name: 'With Tooltip', group: 'Chip')
Widget aleraChipTooltipPreview() => const AleraChip(
  label: '#frontend',
  leading: AleraIcons.tag,
  tooltip: 'frontend',
);

@AleraPreview(name: 'Removable', group: 'Chip')
Widget aleraChipRemovablePreview() =>
    AleraChip(label: 'Alera', onRemove: () {});

@AleraPreview(name: 'Tappable', group: 'Chip')
Widget aleraChipTappablePreview() => AleraChip(
  leading: AleraIcons.workspaceChildren,
  label: '2 children',
  trailing: AleraIcons.chevronDown,
  tooltip: 'Hide Child Workspaces',
  onTap: () {},
);
