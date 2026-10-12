import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/layout/alera_collapsible_section.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Expanded',
  group: 'Collapsible section',
  size: Size(420, 200),
)
Widget aleraCollapsibleSectionPreview() => const AleraCollapsibleSection(
  title: 'Options',
  description: 'Schedule limits, reliability and notifications.',
  initiallyExpanded: true,
  trailing: AleraBadge(label: '2'),
  child: Padding(
    padding: EdgeInsets.only(left: AleraTokens.space24),
    child: Text('Retry Attempts: 2'),
  ),
);

@AleraPreview(
  name: 'Collapsed',
  group: 'Collapsible section',
  size: Size(420, 120),
)
Widget aleraCollapsibleSectionCollapsedPreview() =>
    const AleraCollapsibleSection(
      title: 'Description',
      child: Text('Summarize open pull requests every morning.'),
    );
