/// One command Alera runs in front of the user instead of asking them to paste
/// it into a terminal of their own.
///
/// The command reaches a real PTY, so anything it prompts for - a `sudo`
/// password, a `y/n` confirmation - has somewhere to be typed. That is the
/// whole reason this exists: `ProcessRunner.run` gives no TTY, so a prompt
/// there hangs with nothing to answer it.
class CommandTerminalRequest {
  const CommandTerminalRequest({
    required this.title,
    required this.command,
    this.workingDirectory,
    this.description,
  });

  /// Dialog title, in title case like the rest of the visible copy.
  final String title;

  /// A single portable line. It is typed into the user's interactive shell, so
  /// it must survive whatever they configured: PowerShell 5.1 rejects `&&` at
  /// parse time and nushell removed it, and a second line would land on the
  /// first command's stdin because PTY bytes go to the foreground process.
  final String command;

  /// Directory the shell starts in. Null falls back to the user's home.
  final String? workingDirectory;

  /// Optional caption under the header explaining what the command does.
  final String? description;
}

/// Workspace id shared by every ephemeral command session. Real workspaces are
/// minted as uuids, so this never collides with one.
///
/// The workbench exit coordinator keys off it: a command session belongs to its
/// dialog, not to the workbench, and must not be torn down when its PTY exits.
const String commandTerminalWorkspaceId = '__alera_command_terminal__';

bool isCommandTerminalWorkspaceId(String value) =>
    value == commandTerminalWorkspaceId;

/// Home directory for a command session that names no working directory.
///
/// A GUI-launched app inherits whatever directory the launcher had, which on
/// Windows is typically `C:\Windows\System32`, so falling through to the
/// inherited one would start installers in a place they cannot write.
String? commandTerminalHomeDirectory(Map<String, String> environment) {
  for (final key in const <String>['HOME', 'USERPROFILE']) {
    final value = environment[key]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}
