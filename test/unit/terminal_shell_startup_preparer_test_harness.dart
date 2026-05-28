part of 'terminal_shell_startup_preparer_test.dart';

GhosttyTerminalShellLaunch _launch({
  required String shell,
  List<String> arguments = const <String>[],
  Map<String, String> environment = const <String, String>{},
  String? setupCommand,
}) {
  return GhosttyTerminalShellLaunch(
    label: shell,
    shell: shell,
    arguments: arguments,
    environment: environment,
    setupCommand: setupCommand,
  );
}

String _decodePowerShellEncodedCommand(String encodedCommand) {
  final bytes = base64.decode(encodedCommand);
  final codeUnits = <int>[];
  for (var i = 0; i < bytes.length; i += 2) {
    codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(codeUnits);
}
