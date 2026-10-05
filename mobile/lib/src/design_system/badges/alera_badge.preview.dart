import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Badge Tones', group: 'Badges')
Widget aleraBadgeTonesPreview() => const Padding(
  padding: AleraTokens.pagePadding,
  child: Wrap(
    spacing: AleraTokens.space8,
    runSpacing: AleraTokens.space8,
    children: <Widget>[
      AleraBadge(label: 'Primary'),
      AleraBadge(label: 'Selected', tone: AleraBadgeTone.accent),
      AleraBadge(label: 'Needs Input', tone: AleraBadgeTone.attention),
      AleraBadge(label: 'Blocked', tone: AleraBadgeTone.error),
      AleraBadge(label: 'Done', tone: AleraBadgeTone.success),
      AleraBadge(label: 'Merged', tone: AleraBadgeTone.info),
      AleraBadge(label: 'Reviewed', tone: AleraBadgeTone.done),
    ],
  ),
);

@AleraPreview(name: 'Badge Leading Marks', group: 'Badges')
Widget aleraBadgeLeadingPreview() => const Padding(
  padding: AleraTokens.pagePadding,
  child: Wrap(
    spacing: AleraTokens.space8,
    runSpacing: AleraTokens.space8,
    children: <Widget>[
      AleraBadge(
        label: 'Checks Passing',
        tone: AleraBadgeTone.success,
        icon: AleraIcons.success,
      ),
      AleraBadge(label: 'Live', tone: AleraBadgeTone.success, dot: true),
    ],
  ),
);
