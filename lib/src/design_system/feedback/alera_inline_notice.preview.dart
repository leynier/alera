import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Info', group: 'Inline Notice', size: Size(440, 120))
Widget aleraInlineNoticePreview() => const AleraInlineNotice(
  message: 'Alera is not on Build Mac yet. Add it to create workspaces there.',
);

@AleraPreview(name: 'With action', group: 'Inline Notice', size: Size(440, 160))
Widget aleraInlineNoticeActionPreview() => AleraInlineNotice(
  tone: .warning,
  message: 'This host has not been checked since the last update.',
  child: Align(
    alignment: .centerLeft,
    child: FilledButton(onPressed: () {}, child: const Text('Check Host')),
  ),
);

@AleraPreview(name: 'Error', group: 'Inline Notice', size: Size(440, 120))
Widget aleraInlineNoticeErrorPreview() => const AleraInlineNotice(
  tone: .error,
  message: 'The host refused the connection. Check SSH access and retry.',
);
