import 'package:alera/src/features/workbench/domain/terminal_path_paste.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';

/// Pastes absolute OS paths into [session] after a file/folder drop.
void handleTerminalOsFileDrop({
  required TerminalSessionHandle session,
  required Iterable<String> paths,
}) {
  final text = formatPathsForTerminalPaste(paths);
  if (text.isEmpty) {
    return;
  }
  session.pasteText(text);
  session.requestFocus();
}
