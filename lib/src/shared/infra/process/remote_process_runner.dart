import 'dart:io';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

/// How long the workspace host lets one tool run. The host caps the value it
/// accepts, so a larger request is shortened there rather than refused.
const Duration remoteProcessRunTimeout = Duration(minutes: 2);

/// The runtime request waits a little longer than the tool is allowed to run,
/// so the host's own "timed out" answer arrives instead of a dropped request.
const Duration _requestMargin = Duration(seconds: 40);

/// [ProcessRunner] for a workspace whose checkout lives on another host. `run`
/// becomes a `host.process.run` request the runtime forwards over that host's
/// link, so a forge CLI (`gh`, `glab`, `az`) runs next to the checkout with
/// that host's credentials and login-shell `PATH`.
///
/// `workingDirectory` is a path on the remote host and is sent as-is; the host
/// refuses anything outside the workspace. Only the variables the caller names
/// are sent: the hub's own environment means nothing on another machine and
/// may hold secrets that must not cross hosts.
///
/// `start` is not available: nothing streams over the link, and the features
/// that stream (AI Assist) are forwarded as whole runtime verbs instead.
class RemoteProcessRunner implements ProcessRunner {
  RemoteProcessRunner(
    this._client, {
    required this.workspaceId,
    this.beforeAccess,
    this.timeout = remoteProcessRunTimeout,
  });

  final RuntimeHostClient _client;
  final String workspaceId;
  final Future<void> Function()? beforeAccess;
  final Duration timeout;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final Object? value;
    try {
      await beforeAccess?.call();
      value = await _client.runtimeRequest(
        'host.process.run',
        <String, Object?>{
          'workspaceId': workspaceId,
          'executable': executable,
          'arguments': arguments,
          'cwd': ?workingDirectory,
          if (environment != null && environment.isNotEmpty)
            'environment': environment,
          'timeoutMs': timeout.inMilliseconds,
        },
        timeout + _requestMargin,
      );
    } catch (error) {
      throw ProcessException(executable, arguments, _messageOf(error));
    }
    if (value is! Map) {
      throw ProcessException(
        executable,
        arguments,
        'The workspace host returned no process result.',
      );
    }
    final exitCode = value['exitCode'];
    return ProcessRunOutput(
      exitCode: exitCode is int ? exitCode : -1,
      stdout: value['stdout']?.toString() ?? '',
      stderr: value['stderr']?.toString() ?? '',
    );
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) {
    return Future<StartedProcess>.error(
      ProcessException(
        executable,
        arguments,
        'Streaming processes are not available for a workspace on a remote '
        'host.',
      ),
    );
  }

  static String _messageOf(Object error) {
    if (error is TerminalHostConflictException) {
      return error.message;
    }
    return error.toString();
  }
}
