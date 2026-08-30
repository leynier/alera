import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:alera/src/shared/infra/process/rust_process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class BundledSidecarVersionProbe {
  Future<BundledSidecarVersion> probe();
}

final class ProcessBundledSidecarVersionProbe({
  AleraCliResolver? cliResolver,
  Future<Directory> Function()? applicationSupportDirectory,
  Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })?
  runProcess,
}) implements BundledSidecarVersionProbe {
  this
    : _cliResolver = cliResolver ?? DefaultAleraCliResolver(),
      _applicationSupportDirectory =
          applicationSupportDirectory ?? getApplicationSupportDirectory,
      _runProcess = runProcess ?? _runThroughRustRunner;

  final AleraCliResolver _cliResolver;
  final Future<Directory> Function() _applicationSupportDirectory;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  _runProcess;

  BundledSidecarVersion? _cached;

  /// The sidecar is a console binary, so probing it from the GUI runner has to
  /// go through the Rust runner or Windows shows a console window for it.
  static Future<ProcessResult> _runThroughRustRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final output = await const RustProcessRunner().run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    return ProcessResult(0, output.exitCode, output.stdout, output.stderr);
  }

  @override
  Future<BundledSidecarVersion> probe() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final support = await _applicationSupportDirectory();
    final runtimeDir = p.join(support.path, 'terminal_host');
    final command = await _cliResolver.resolve(runtimeDir: runtimeDir);
    final result = await _runProcess(command.executable, <String>[
      ...command.prefixArguments,
      'version',
      '--json',
    ], workingDirectory: command.workingDirectory);
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to resolve bundled sidecar version '
        '(exit ${result.exitCode}): ${result.stderr}',
      );
    }
    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is! Map) {
      throw const FormatException(
        'Bundled sidecar version payload must be a JSON object.',
      );
    }
    final version = decoded['cliVersion'];
    if (version is! String || version.isEmpty) {
      throw const FormatException(
        'Bundled sidecar version payload is missing cliVersion.',
      );
    }
    final commit = decoded['cliCommit'];
    final probed = BundledSidecarVersion(
      version: version,
      commit: commit is String && commit.isNotEmpty ? commit : null,
    );
    _cached = probed;
    return probed;
  }
}
