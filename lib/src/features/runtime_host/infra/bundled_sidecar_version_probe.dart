import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class BundledSidecarVersionProbe {
  Future<BundledSidecarVersion> probe();
}

final class ProcessBundledSidecarVersionProbe
    implements BundledSidecarVersionProbe {
  ProcessBundledSidecarVersionProbe({
    AleraCliResolver? cliResolver,
    Future<Directory> Function()? applicationSupportDirectory,
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    })?
    runProcess,
  }) : _cliResolver = cliResolver ?? DefaultAleraCliResolver(),
       _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory,
       _runProcess =
           runProcess ??
           ((executable, arguments, {workingDirectory}) => Process.run(
             executable,
             arguments,
             workingDirectory: workingDirectory,
           ));

  final AleraCliResolver _cliResolver;
  final Future<Directory> Function() _applicationSupportDirectory;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  _runProcess;

  BundledSidecarVersion? _cached;

  @override
  Future<BundledSidecarVersion> probe() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final support = await _applicationSupportDirectory();
    final runtimeDir = p.join(support.path, 'terminal_host');
    final command = await _cliResolver.resolve(runtimeDir: runtimeDir);
    final result = await _runProcess(
      command.executable,
      <String>[...command.prefixArguments, 'version', '--json'],
      workingDirectory: command.workingDirectory,
    );
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
