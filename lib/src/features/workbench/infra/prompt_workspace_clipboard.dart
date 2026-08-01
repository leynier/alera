import 'package:alera/src/features/workbench/infra/terminal_clipboard.dart';

/// Clipboard operations needed by the desktop prompt workspace flow.
abstract interface class PromptWorkspaceClipboard {
  Future<String?> readText();

  Future<String?> saveImageAsTempFile();
}

final class NativePromptWorkspaceClipboard implements PromptWorkspaceClipboard {
  const NativePromptWorkspaceClipboard({
    this._clipboard = const NativeTerminalClipboard(),
  });

  final TerminalClipboard _clipboard;

  @override
  Future<String?> readText() => _clipboard.readText();

  @override
  Future<String?> saveImageAsTempFile() => _clipboard.saveImageAsTempFile();
}
