import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/layout/alera_choice_dialog.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Busy Quit', group: 'Choice Dialog', size: Size(480, 320))
WidgetBuilder aleraChoiceDialogPreview() =>
    (context) => const AleraChoiceDialog<String>(
      title: 'Runtime Still Has Work',
      message:
          'The runtime has 2 open agent(s) and 1 active terminal session(s). '
          'You can quit and leave the runtime running, or force stop it.',
      primaryLabel: 'Quit And Leave Runtime Open',
      primaryValue: 'leave',
      secondaryLabel: 'Force Stop And Quit',
      secondaryValue: 'force',
      destructiveSecondary: true,
    );
