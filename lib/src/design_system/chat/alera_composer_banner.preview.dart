import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/chat/alera_composer_banner.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Composer Banner', group: 'Chat', size: Size(560, 120))
Widget composerBannerPreview() => DecoratedBox(
  decoration: BoxDecoration(
    color: AleraTokens.surfaceVariant,
    borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
    border: Border.all(color: AleraTokens.border),
  ),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      AleraComposerBanner(
        title: 'Editing Queued Message',
        detail: 'Its 2 attachments stay as queued',
        cancelShortcutLabel: 'Esc',
        onCancel: () {},
      ),
      const SizedBox(height: AleraTokens.space48),
    ],
  ),
);
