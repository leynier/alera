import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/alera_cli_sidecar.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class RuntimeProxyClient {
  RuntimeProxyClient({
    required this.processRunner,
    AleraCliResolver? cliResolver,
    Future<Directory> Function()? applicationSupportDirectory,
  }) : _cliResolver = cliResolver ?? DefaultAleraCliResolver(),
       _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory;

  final ProcessRunner processRunner;
  final AleraCliResolver _cliResolver;
  final Future<Directory> Function() _applicationSupportDirectory;

  Future<Map<String, Object?>> request({
    required String hostId,
    required SshTarget? target,
    required String type,
    required Map<String, Object?> payload,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final invocation = hostId == 'local'
        ? await _localInvocation()
        : _remoteInvocation(target);
    final process = await processRunner.start(
      invocation.executable,
      invocation.arguments,
      workingDirectory: invocation.workingDirectory,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdinWrite(
      utf8.encode(
        '${jsonEncode(<String, Object?>{'id': 1, 'type': type, 'payload': payload})}\n',
      ),
    );
    process.stdinClose();
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      final output = await stdout;
      final diagnostic = await stderr;
      if (exitCode != 0) {
        throw StateError(
          diagnostic.trim().isEmpty
              ? 'Runtime proxy exited with code $exitCode.'
              : diagnostic.trim(),
        );
      }
      final line = output
          .split('\n')
          .map((value) => value.trim())
          .firstWhere((value) => value.isNotEmpty);
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException(
          'Runtime proxy response must be a JSON object.',
        );
      }
      final response = Map<String, Object?>.from(decoded);
      if (response['ok'] != true) {
        throw StateError(
          (response['error'] as String?) ?? 'Runtime proxy request failed.',
        );
      }
      final responsePayload = response['payload'];
      if (responsePayload is! Map) {
        throw const FormatException(
          'Runtime proxy payload must be a JSON object.',
        );
      }
      return Map<String, Object?>.from(responsePayload);
    } on TimeoutException {
      process.kill();
      throw TimeoutException('Runtime proxy request timed out.', timeout);
    }
  }

  Future<_RuntimeProxyInvocation> _localInvocation() async {
    final support = await _applicationSupportDirectory();
    final runtimeDir = p.join(support.path, 'terminal_host');
    final command = await _cliResolver.resolve(runtimeDir: runtimeDir);
    return _RuntimeProxyInvocation(
      executable: command.executable,
      arguments: <String>[...command.prefixArguments, 'runtime-proxy'],
      workingDirectory: command.workingDirectory,
    );
  }

  _RuntimeProxyInvocation _remoteInvocation(SshTarget? target) {
    if (target == null) {
      throw StateError('Remote quota host is not configured.');
    }
    if (target.bootstrapStatus != SshBootstrapStatus.installed) {
      throw StateError('Install the Alera runtime on this remote host first.');
    }
    final destination = target.username.trim().isEmpty
        ? target.host
        : '${target.username}@${target.host}';
    return _RuntimeProxyInvocation(
      executable: 'ssh',
      arguments: <String>[
        '-p',
        target.port.toString(),
        '-o',
        'BatchMode=yes',
        '-o',
        'ConnectTimeout=15',
        '-o',
        'StrictHostKeyChecking=accept-new',
        destination,
        _remoteCommand(target),
      ],
    );
  }

  String _remoteCommand(SshTarget target) {
    final installDir =
        target.installDir ??
        (target.runtimePlatform == 'windows'
            ? r'%LOCALAPPDATA%\Alera\runtime'
            : '~/.alera/runtime');
    if (target.runtimePlatform == 'windows' || target.platform == 'windows') {
      final localAppDataSuffix = installDir
          .substring(
            installDir.startsWith(r'%LOCALAPPDATA%\')
                ? r'%LOCALAPPDATA%'.length
                : 0,
          )
          .replaceAll("'", "''");
      final installExpression = installDir.startsWith(r'%LOCALAPPDATA%\')
          ? "\$env:LOCALAPPDATA + '$localAppDataSuffix'"
          : "'${installDir.replaceAll("'", "''")}'";
      return 'powershell -NoProfile -Command '
          '"& (Join-Path ($installExpression) '
          '\'current\\alera.exe\') runtime-proxy"';
    }
    final executablePath = installDir.startsWith('~/')
        ? '\$HOME/${installDir.substring(2)}/current/alera'
        : '$installDir/current/alera';
    return r'"$SHELL" -lc ' +
        _shellQuote('${_shellQuote(executablePath)} runtime-proxy');
  }
}

class _RuntimeProxyInvocation {
  const _RuntimeProxyInvocation({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
