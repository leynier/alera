import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Scaffold', group: 'Dialog', size: Size(460, 240))
WidgetBuilder aleraDialogPreview() =>
    (context) => AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AleraDialogHeader(title: 'Create Workspace', onClose: () {}),
            const SizedBox(height: AleraTokens.space16),
            Text(
              'Dialog body content goes here.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
