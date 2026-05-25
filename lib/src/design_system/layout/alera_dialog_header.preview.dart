import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Title + close',
  group: 'Dialog header',
  size: Size(360, 56),
)
Widget aleraDialogHeaderPreview() =>
    AleraDialogHeader(title: 'View options', onClose: () {});
