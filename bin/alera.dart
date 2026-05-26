import 'dart:io';

import 'package:alera/src/cli/alera_cli_runner.dart';

Future<void> main(List<String> args) async {
  exitCode = await runAleraCli(args);
}
