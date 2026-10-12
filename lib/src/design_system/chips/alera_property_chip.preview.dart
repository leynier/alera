import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/chips/alera_property_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'States', group: 'Property chip', size: Size(560, 140))
Widget aleraPropertyChipPreview() => Wrap(
  spacing: AleraTokens.space8,
  runSpacing: AleraTokens.space8,
  children: <Widget>[
    AleraPropertyChip(
      icon: AleraIcons.schedule,
      value: 'Weekdays at 09:00',
      onTap: () {},
    ),
    AleraPropertyChip(
      icon: AleraIcons.folder,
      label: 'In',
      value: 'alera / main',
      fromContext: true,
      onTap: () {},
    ),
    AleraPropertyChip(
      icon: AleraIcons.agent,
      value: 'Opus',
      active: true,
      onTap: () {},
    ),
    AleraPropertyChip(
      icon: AleraIcons.folder,
      value: 'Choose Destination',
      hasError: true,
      tooltip: 'Choose where the automation runs.',
      onTap: () {},
    ),
    AleraPropertyChip(
      label: 'Reuse',
      value: 'Same Conversation',
      onTap: () {},
      onClear: () {},
    ),
    const AleraPropertyChip(icon: AleraIcons.agent, value: 'Disabled'),
  ],
);
