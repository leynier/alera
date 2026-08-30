import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Selected Run', group: 'Activity row', size: Size(320, 180))
Widget selectedActivityRowPreview() => AleraActivityRow(
  title: 'Add reviewed workflow plans',
  subtitle: 'Attention · 2 Pending Gates',
  metadata: 'Alera / feature-delivery',
  selected: true,
  statusColor: AleraTokens.warning,
  onPressed: () {},
);

@AleraPreview(name: 'Task', group: 'Activity row', size: Size(320, 160))
Widget taskActivityRowPreview() => AleraActivityRow(
  title: 'Validate the result contract',
  subtitle: 'Running',
  metadata: 'Depends On: foundation-schema',
  onPressed: () {},
);
