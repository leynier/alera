import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_command_line.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Plain', group: 'Command line', size: Size(520, 120))
Widget aleraCommandLinePreview() => const AleraCommandLine(
  command: 'sudo apt-get install --only-upgrade alera',
);

@AleraPreview(name: 'With action', group: 'Command line', size: Size(520, 120))
Widget aleraCommandLineWithActionPreview() => AleraCommandLine(
  command: 'npx skills add https://github.com/leynier/alera --global',
  trailing: FilledButton.icon(
    onPressed: () {},
    icon: const Icon(AleraIcons.terminal, size: 16),
    label: const Text('Run'),
  ),
);
