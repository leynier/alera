import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/chat/alera_composer_banner.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Composer Banner', group: 'Chat')
Widget composerBannerPreview() => AleraComposerBanner(
  title: 'Editing Queued Message',
  detail: 'Its 2 attachments stay as queued',
  onCancel: () {},
);
