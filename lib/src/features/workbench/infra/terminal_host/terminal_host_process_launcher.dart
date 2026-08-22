import 'dart:io';
import 'package:alera/src/core/build_flavor.dart';

import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _compiledRuntimeArchivePublicKey = String.fromEnvironment(
  'ALERA_UPDATE_MANIFEST_PUBLIC_KEY',
);

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
        if (config.crashReporting) '--crash-reporting',
      ],
      workingDirectory: command.workingDirectory,
      mode: ProcessStartMode.detached,
      environment: await _terminalHostEnvironment(),
    );
  }
}

Future<Map<String, String>> _terminalHostEnvironment() async {
  final environment = <String, String>{
    'ALERA_TERMINAL_HOST': '1',
    // The sidecar tags its crash reports with this so dev noise can be filtered
    // out in Sentry; it cannot infer the flavor of the app that launched it.
    'ALERA_FLAVOR': kAleraFlavor,
  };
  if (_compiledRuntimeArchivePublicKey.isNotEmpty) {
    environment['ALERA_RUNTIME_ARCHIVE_PUBLIC_KEY'] =
        _compiledRuntimeArchivePublicKey;
  }
  final support = await getApplicationSupportDirectory();
  environment['ALERA_WHISPER_MODEL_ROOT'] = p.join(
    support.path,
    'models',
    'ai-dictation',
  );
  return environment;
}

// coverage:ignore-end
