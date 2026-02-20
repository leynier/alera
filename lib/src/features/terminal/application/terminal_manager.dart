import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/terminal/application/terminal_session.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';

class TerminalManager {
  TerminalManager({required ProcessRunner processRunner})
      : _processRunner = processRunner;

  final ProcessRunner _processRunner;
  final Uuid _uuid = const Uuid();

  Future<TerminalSession> create({required String cwd}) async {
    final terminal = Terminal(maxLines: 10000);

    try {
      final pty = Pty.start(
        _defaultShell,
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
        workingDirectory: cwd,
      );

      final outSub = pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .listen(terminal.write);

      terminal.onOutput = (data) {
        pty.write(const Utf8Encoder().convert(data));
      };

      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        pty.resize(height, width);
      };

      pty.exitCode.then((code) {
        terminal.write('\r\n[process exited: $code]\r\n');
      });

      return TerminalSession(
        id: _uuid.v4(),
        terminal: terminal,
        backendType: TerminalBackendType.pty,
        dispose: () async {
          await outSub.cancel();
          pty.kill();
        },
      );
    } catch (_) {
      final process = await _processRunner.start(
        _defaultShell,
        _shellArguments,
        workingDirectory: cwd,
      );

      final stdoutSub = process.stdout
          .transform(const Utf8Decoder())
          .listen(terminal.write);
      final stderrSub = process.stderr
          .transform(const Utf8Decoder())
          .listen(terminal.write);

      terminal.onOutput = (data) {
        process.stdinWrite(const Utf8Encoder().convert(data));
      };

      process.exitCode.then((code) {
        terminal.write('\r\n[process exited: $code]\r\n');
      });

      return TerminalSession(
        id: _uuid.v4(),
        terminal: terminal,
        backendType: TerminalBackendType.pipes,
        dispose: () async {
          await stdoutSub.cancel();
          await stderrSub.cancel();
          process.kill();
        },
      );
    }
  }

  String get _defaultShell {
    if (Platform.isWindows) {
      return 'cmd.exe';
    }

    return Platform.environment['SHELL'] ?? '/bin/bash';
  }

  List<String> get _shellArguments {
    if (Platform.isWindows) {
      return const <String>[];
    }

    return const <String>['-i'];
  }
}
