import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Neutral', group: 'Badge')
Widget aleraBadgePreview() => const AleraBadge(label: 'Primary');

@AleraPreview(name: 'Tones', group: 'Badge')
Widget aleraBadgeTonesPreview() => const Wrap(
  spacing: 8,
  runSpacing: 8,
  children: <Widget>[
    AleraBadge(label: 'Neutral'),
    AleraBadge(label: 'Accent', tone: .accent),
    AleraBadge(label: 'Needs Input', tone: .attention),
    AleraBadge(label: 'Done', tone: .success),
    AleraBadge(label: 'Blocked', tone: .error),
    AleraBadge(label: 'Review', tone: .info),
    AleraBadge(label: 'Merged', tone: .done),
  ],
);

@AleraPreview(name: 'Leading icon and dot', group: 'Badge')
Widget aleraBadgeLeadingPreview() => const Wrap(
  spacing: 8,
  children: <Widget>[
    AleraBadge(
      label: 'Checks Passing',
      tone: .success,
      icon: AleraIcons.success,
    ),
    AleraBadge(label: 'Running', tone: .attention, dot: true),
  ],
);
