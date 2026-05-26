// coverage:ignore-file

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_server.dart';

Future<void> runAleraTerminalHostServer({
  required String runtimeDir,
  required String controlFilePath,
  required String token,
}) async {
  await AleraTerminalHostServer(
    runtimeDir: runtimeDir,
    controlFilePath: controlFilePath,
    token: token,
  ).run();
}
