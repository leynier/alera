part of 'terminal_runtime.dart';

Future<void> _deliverTerminalProcessStartup({
  required TerminalPtySession session,
  required GhosttyTerminalShellLaunch launch,
  required String interactiveShell,
  required String? initialCommand,
  required bool Function() isCurrent,
}) async {
  final setupCommand = launch.setupCommand;
  if (setupCommand != null && setupCommand.isNotEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!isCurrent()) {
      return;
    }
    if (!await session.writeBytesAndWait(utf8.encode(setupCommand))) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  if (initialCommand == null || initialCommand.isEmpty) {
    return;
  }
  await Future<void>.delayed(const Duration(milliseconds: 120));
  if (!isCurrent()) {
    return;
  }
  if (shouldUseBracketedPasteForStartupCommand(initialCommand) &&
      terminalShellSupportsBracketedPaste(interactiveShell)) {
    if (!await session.writeBytesAndWait(
      buildAgentPromptPasteBytes(initialCommand),
    )) {
      return;
    }
    await Future<void>.delayed(terminalAgentPromptSubmitDelay);
    if (isCurrent()) {
      await session.writeBytesAndWait(utf8.encode('\r'));
    }
    return;
  }
  await session.writeBytesAndWait(
    buildPlainStartupCommandBytes(initialCommand),
  );
}
