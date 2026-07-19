import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Rename Host', group: 'Rename Dialog')
Widget aleraRenameDialogPreview() => const AleraRenameDialog(
  title: 'Rename Host',
  labelText: 'Host Name',
  initialValue: 'Alera Workstation',
  helperText: 'Leave Empty To Use The Advertised Host Name',
  allowEmpty: true,
);
