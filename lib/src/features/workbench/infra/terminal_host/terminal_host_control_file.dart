part of 'terminal_host_client.dart';

/// Reading, validating, and clearing the host control file.
///
/// Top-level rather than methods on the client, following `_controlAcceptsHello`:
/// none of this touches client state, and keeping it out of the class is what
/// keeps the client file reviewable.

/// Refuse to launch when a live host of another protocol version already owns
/// this runtime directory.
///
/// `_readControl` answers null for such a file, which is the same answer it
/// gives for no file at all, so without this the launch went ahead against a
/// directory that was already taken, re-read the same incompatible file every
/// hundred milliseconds, and failed the whole startup timeout later with
/// "did not start in time" and no last error. The cause was known at the
/// first read; this reports it there instead.
///
/// The usual way to arrive here is an app update leaving the previous
/// `alera terminal-host` running, which is what `make host-stop` exists for.
/// A control file whose host is gone is stale rather than blocking, so it is
/// deleted and the launch proceeds.
Future<void> _failIfIncompatibleHostHoldsRuntime(
  _TerminalHostPaths runtime,
) async {
  for (final file in <File>[runtime.controlFile, runtime.runtimeControlFile]) {
    final version = await _readIncompatibleProtocolVersion(file);
    if (version == null) {
      continue;
    }
    if (await _portIsListening(version.port)) {
      throw StateError(
        'A terminal host speaking protocol ${version.protocolVersion} is '
        'already running, but this app speaks '
        '$aleraTerminalHostProtocolVersion. Stop the running host '
        '(`make host-stop`, or quit every other Alera build) and try again.',
      );
    }
    await _deleteControlFile(file);
  }
}

/// The protocol version and port of a control file this app cannot speak, or
/// null when the file is absent, unreadable, or compatible.
Future<({int protocolVersion, int port})?> _readIncompatibleProtocolVersion(
  File file,
) async {
  try {
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    final map = asTerminalHostMap(decoded, 'terminal host control');
    final version = map['protocolVersion'];
    final port = map['port'];
    if (version is! int ||
        version == aleraTerminalHostProtocolVersion ||
        port is! int) {
      return null;
    }
    return (protocolVersion: version, port: port);
  } catch (_) {
    // An unreadable file is not evidence that anything owns the directory.
    return null;
  }
}

/// Whether something still answers on the port a control file advertises.
///
/// A bare connect rather than a hello: a host of another protocol version
/// would reject our hello, so a handshake cannot tell it apart from a dead
/// one, and accepting the connection is all the proof of ownership needed.
Future<bool> _portIsListening(int port) async {
  Socket? socket;
  try {
    socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: _terminalHostConnectTimeout,
    );
    return true;
  } catch (_) {
    return false;
  } finally {
    socket?.destroy();
  }
}

Future<_TerminalHostControl?> _readControl(File file) async {
  try {
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    final map = asTerminalHostMap(decoded, 'terminal host control');
    if (map['protocolVersion'] != aleraTerminalHostProtocolVersion) {
      return null;
    }
    final capabilities = asTerminalHostStringList(map['runtimeCapabilities']);
    final port = map['port'];
    final token = map['token'];
    if (port is! int || token is! String || token.isEmpty) {
      return null;
    }
    return _TerminalHostControl(
      port: port,
      token: token,
      supportsRuntime:
          capabilities.contains(aleraRuntimeHostCapability) &&
          capabilities.contains(aleraRuntimeHostBootstrapCapability) &&
          capabilities.contains(aleraRuntimeHostManagedWorkspaceCapability),
      supportsOrchestration: capabilities.contains(
        aleraRuntimeHostOrchestrationCapability,
      ),
      supportsBinaryFrames: capabilities.contains(
        aleraRuntimeHostBinaryFramesCapability,
      ),
      supportsTerminalRestart: capabilities.contains(
        aleraRuntimeHostTerminalRestartCapability,
      ),
      supportsDeferredInput: capabilities.contains(
        aleraRuntimeHostTerminalDeferredInputCapability,
      ),
      supportsTerminalPulse: capabilities.contains(
        aleraRuntimeHostTerminalPulseCapability,
      ),
      supportsRemoteAiDictation: capabilities.contains(
        aleraRuntimeHostRemoteAiDictationCapability,
      ),
      supportsWorkspaceSections: capabilities.contains(
        aleraRuntimeHostWorkspaceSectionsCapability,
      ),
    );
  } catch (_) {
    return null;
  }
}

Future<void> _deleteControlFile(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
}
