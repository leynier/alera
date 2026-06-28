import 'dart:io';

import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

abstract interface class TerminalHostProcessLauncher {
  Future<void> start({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
    required TerminalHostConfig config,
  });
}

// coverage:ignore-start
final class DefaultTerminalHostProcessLauncher
    implements TerminalHostProcessLauncher {
  factory DefaultTerminalHostProcessLauncher({AleraCliResolver? cliResolver}) {
    return DefaultTerminalHostProcessLauncher._(
      cliResolver ?? DefaultAleraCliResolver(),
    );
  }

  DefaultTerminalHostProcessLauncher._(this._cliResolver);

  final AleraCliResolver _cliResolver;

  @override
  Future<void> start({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
    required TerminalHostConfig config,
  }) async {
    final command = await _cliResolver.resolve(runtimeDir: runtimeDir);
    await Process.start(
      command.executable,
      <String>[
        ...command.prefixArguments,
        aleraRuntimeHostCommand,
        '--runtime-dir',
        runtimeDir,
        '--control-file',
        controlFilePath,
        '--token',
        token,
        '--empty-shutdown-delay-seconds',
        config.emptyShutdownDelaySeconds.toString(),
        '--detached-session-shutdown-delay-seconds',
        config.detachedSessionShutdownDelaySeconds.toString(),
        '--scrollback-bytes',
        config.scrollbackBytes.toString(),
      ],
      workingDirectory: command.workingDirectory,
      mode: ProcessStartMode.detached,
      environment: const <String, String>{'ALERA_TERMINAL_HOST': '1'},
    );
  }
}

// coverage:ignore-end
