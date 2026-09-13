import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Read-Only Notice', group: 'Feedback')
Widget aleraNoticePreview() => const AleraNotice(
  icon: AleraIcons.info,
  message: 'Source control is read-only on mobile. Stage, unstage, and commit stay on desktop.',
);

@AleraPreview(name: 'Notice With Action', group: 'Feedback')
Widget aleraNoticeActionPreview() => AleraNotice(
  icon: AleraIcons.warning,
  message: 'Could not refresh source control. Runtime connection lost.',
  action: TextButton(onPressed: () {}, child: const Text('Retry')),
);
