import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Destructive',
  group: 'Confirm dialog',
  size: Size(460, 260),
)
WidgetBuilder aleraConfirmDialogPreview() =>
    (context) => const AleraConfirmDialog(
      title: 'Remove workspace?',
      message: 'This removes the worktree and deletes its branch.',
      confirmLabel: 'Remove',
      destructive: true,
    );
