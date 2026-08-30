import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';

/// Clipboard operations needed by the desktop prompt workspace flow.
abstract interface class PromptWorkspaceClipboard {
  Future<String?> readText();

  Future<String?> saveImageAsTempFile();
}

final class const NativePromptWorkspaceClipboard({
  final TerminalClipboard _clipboard = const NativeTerminalClipboard(),
}) implements PromptWorkspaceClipboard {
  @override
  Future<String?> readText() => _clipboard.readText();

  @override
  Future<String?> saveImageAsTempFile() => _clipboard.saveImageAsTempFile();
}
