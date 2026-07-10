part of 'terminal_runtime_native_test.dart';

GhosttyTerminalShellLaunch _launch(
  String label, {
  required String shell,
  List<String> arguments = const <String>[],
  Map<String, String> environment = const <String, String>{
    'TERM': 'xterm-256color',
  },
  String? setupCommand,
}) {
  return GhosttyTerminalShellLaunch(
    label: label,
    shell: shell,
    arguments: arguments,
    environment: environment,
    setupCommand: setupCommand,
  );
}

String? get _skipLinuxCiRealPtyReason {
  if (Platform.isLinux && Platform.environment['CI'] == 'true') {
    return 'Linux CI uses the Rust terminal-host sidecar E2E for real PTY coverage.';
  }
  return null;
}

Workspace _workspace({String id = 'workspace-1', String path = '/repo/alera'}) {
  final now = DateTime.utc(2026, 5, 25, 12);
  return Workspace(
    id: id,
    projectId: 'project-1',
    name: 'Main',
    branch: 'main',
    path: path,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _tab({
  String id = 'tab-1',
  String workspaceId = 'workspace-1',
  String title = 'Terminal 1',
  Map<String, Object?> payload = const <String, Object?>{},
}) {
  final now = DateTime.utc(2026, 5, 25, 12);
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    title: title,
    createdAt: now,
    updatedAt: now,
    payload: payload,
  );
}

String _decodePowerShellEncodedCommand(String encodedCommand) {
  final bytes = base64.decode(encodedCommand);
  final codeUnits = <int>[];
  for (var i = 0; i < bytes.length; i += 2) {
    codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(codeUnits);
}

class _FakeTerminalPtySessionFactory implements TerminalPtySessionFactory {
  _FakeTerminalPtySessionFactory({List<_FakeTerminalPtySession>? sessions})
    : _availableSessions = sessions ?? <_FakeTerminalPtySession>[];

  final List<_FakeTerminalPtySession> _availableSessions;
  final List<_FakeTerminalPtySession> createdSessions =
      <_FakeTerminalPtySession>[];

  @override
  TerminalPtySession create({
    required String sessionId,
    required String workspaceId,
    required String tabId,
  }) {
    final session = _availableSessions.removeAt(0);
    createdSessions.add(session);
    return session;
  }
}

class _RecordingTerminalShellStartupPreparer
    implements TerminalShellStartupPreparer {
  final List<GhosttyTerminalShellLaunch> launches =
      <GhosttyTerminalShellLaunch>[];

  @override
  GhosttyTerminalShellLaunch prepare(GhosttyTerminalShellLaunch launch) {
    launches.add(launch);
    return launch;
  }
}

class _FakeTerminalPtySession implements TerminalPtySession {
  _FakeTerminalPtySession({this.startError, this.startCompleter});

  final Object? startError;
  final Completer<void>? startCompleter;
  final StreamController<TerminalPtySessionEvent> _events =
      StreamController<TerminalPtySessionEvent>.broadcast();
  final List<List<int>> writes = <List<int>>[];
  final List<_ResizeCall> resizeCalls = <_ResizeCall>[];
  final List<bool> outputPausedCalls = <bool>[];
  GhosttyTerminalShellLaunch? startedLaunch;
  String? startedWorkingDirectory;
  int? startedCols;
  int? startedRows;
  Future<void> Function()? onProcessCreated;
  bool disposed = false;
  bool terminated = false;
  bool startedNewProcessValue = true;

  @override
  Stream<TerminalPtySessionEvent> get events => _events.stream;

  @override
  bool get startedNewProcess => startedNewProcessValue;

  @override
  Future<void> start({
    required GhosttyTerminalShellLaunch launch,
    required String workingDirectory,
    required int cols,
    required int rows,
    Future<void> Function()? onProcessCreated,
  }) async {
    startedLaunch = launch;
    startedWorkingDirectory = workingDirectory;
    startedCols = cols;
    startedRows = rows;
    this.onProcessCreated = onProcessCreated;
    if (startError case final Object error) {
      throw error;
    }
    if (startCompleter case final completer?) {
      await completer.future;
    }
    if (startedNewProcessValue) {
      await onProcessCreated?.call();
    }
  }

  Future<void> remint() async => onProcessCreated?.call();

  @override
  bool writeBytes(List<int> bytes) {
    writes.add(List<int>.from(bytes));
    return bytes.isNotEmpty;
  }

  @override
  Future<bool> writeBytesAndWait(List<int> bytes) async => writeBytes(bytes);

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {
    resizeCalls.add(
      _ResizeCall(
        cols: cols,
        rows: rows,
        cellWidthPx: cellWidthPx,
        cellHeightPx: cellHeightPx,
      ),
    );
  }

  @override
  Future<void> setOutputPaused(bool paused) async {
    outputPausedCalls.add(paused);
  }

  void emitOutput(List<int> data) {
    if (_events.isClosed) {
      return;
    }
    _events.add(TerminalPtyOutputEvent(Uint8List.fromList(data)));
  }

  void emitSnapshot(List<int> data, {bool resetInteractionModes = false}) {
    if (_events.isClosed) {
      return;
    }
    _events.add(
      TerminalPtySnapshotEvent(
        Uint8List.fromList(data),
        resetInteractionModes: resetInteractionModes,
      ),
    );
  }

  void emitExit(int exitCode) {
    if (_events.isClosed) {
      return;
    }
    _events.add(TerminalPtyExitEvent(exitCode));
  }

  void emitError(Object error) {
    if (_events.isClosed) {
      return;
    }
    _events.add(TerminalPtyErrorEvent(error));
  }

  @override
  void dispose() {
    if (disposed) {
      return;
    }
    disposed = true;
    unawaited(_events.close());
  }

  @override
  void terminate() {
    terminated = true;
    dispose();
  }
}

class _FakeExternalUriLauncher implements ExternalUriLauncher {
  _FakeExternalUriLauncher({this.error});

  final Object? error;
  final List<Uri> openedUris = <Uri>[];

  @override
  Future<void> open(Uri uri) async {
    openedUris.add(uri);
    if (error case final Object error) {
      throw error;
    }
  }
}

class _ResizeCall {
  const _ResizeCall({
    required this.cols,
    required this.rows,
    required this.cellWidthPx,
    required this.cellHeightPx,
  });

  final int cols;
  final int rows;
  final int cellWidthPx;
  final int cellHeightPx;

  @override
  bool operator ==(Object other) {
    return other is _ResizeCall &&
        other.cols == cols &&
        other.rows == rows &&
        other.cellWidthPx == cellWidthPx &&
        other.cellHeightPx == cellHeightPx;
  }

  @override
  int get hashCode => Object.hash(cols, rows, cellWidthPx, cellHeightPx);
}

const int _oRdOnly = 0;

final ffi.DynamicLibrary _libcForTesting = ffi.DynamicLibrary.process();
final int Function(ffi.Pointer<Utf8>, int) _openForTesting = _libcForTesting
    .lookupFunction<_OpenNative, _OpenDart>('open');
final int Function(int) _closeForTesting = _libcForTesting
    .lookupFunction<_CloseNative, _CloseDart>('close');

typedef _OpenNative = ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32);
typedef _OpenDart = int Function(ffi.Pointer<Utf8>, int);
typedef _CloseNative = ffi.Int32 Function(ffi.Int32);
typedef _CloseDart = int Function(int);
