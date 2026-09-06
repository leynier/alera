import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'New Tab', group: 'Action Sheet')
Widget aleraActionSheetPreview() => const AleraActionSheet<String>(
  entries: <AleraActionSheetEntry<String>>[
    AleraActionSheetEntry<String>(
      value: 'terminal',
      label: 'New Terminal',
      leading: Icon(Icons.terminal),
    ),
    AleraActionSheetEntry<String>(
      value: 'editor',
      label: 'New Editor',
      leading: Icon(Icons.edit_outlined),
    ),
  ],
);
