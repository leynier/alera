import 'package:xterm/xterm.dart';

enum TerminalBackendType { pty, pipes }

class TerminalSession {
  TerminalSession({
    required this.id,
    required this.terminal,
    required this.backendType,
    required this.dispose,
  });

  final String id;
  final Terminal terminal;
  final TerminalBackendType backendType;
  final Future<void> Function() dispose;
}
