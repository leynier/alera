// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:portable_pty/portable_pty.dart';
import 'package:xterm/xterm.dart' as xterm;

abstract class TerminalSessionHandle extends ChangeNotifier {
  String get tabId;

  String get workspaceId;

  String get displayTitle;

  bool get isRunning;

  bool get isStarting;

  String? get errorMessage;

  Future<void> ensureStarted();

  Future<void> restart();

  Widget buildView({Key? key, bool autofocus = false});
}

abstract interface class TerminalRuntime {
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required TerminalTabRecord tab,
  });

  void closeTab(String tabId);

  void closeWorkspace(String workspaceId);

  void dispose();
}

class XtermTerminalRuntime implements TerminalRuntime {
  final Map<String, _XtermTerminalSessionHandle> _sessions =
      <String, _XtermTerminalSessionHandle>{};

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required TerminalTabRecord tab,
  }) {
    return _sessions
        .putIfAbsent(tab.id, () {
          return _XtermTerminalSessionHandle(workspace: workspace, tab: tab);
        })
        .sync(workspace: workspace, tab: tab);
  }

  @override
  void closeTab(String tabId) {
    _sessions.remove(tabId)?.dispose();
  }

  @override
  void closeWorkspace(String workspaceId) {
    final removed = _sessions.entries
        .where((entry) => entry.value.workspaceId == workspaceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final tabId in removed) {
      _sessions.remove(tabId)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}

class _XtermTerminalSessionHandle extends TerminalSessionHandle {
  _XtermTerminalSessionHandle({
    required Workspace workspace,
    required TerminalTabRecord tab,
  }) : _workspace = workspace,
       _tab = tab {
    _terminal = _createTerminal();
    _decodedOutputSub = _ptyOutputController.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_handleTerminalOutput);
  }

  Workspace _workspace;
  TerminalTabRecord _tab;
  late xterm.Terminal _terminal;
  final xterm.TerminalController _terminalController =
      xterm.TerminalController();
  final StreamController<List<int>> _ptyOutputController =
      StreamController<List<int>>();
  late final StreamSubscription<String> _decodedOutputSub;
  _MacOsPtySession? _macOsPtySession;
  Timer? _pendingPtyResizeTimer;
  _TerminalPtySize? _pendingPtySize;

  bool _starting = false;
  bool _started = false;
  bool _running = false;
  String _title = '';
  String? _errorMessage;
  bool _disposed = false;

  @override
  String get tabId => _tab.id;

  @override
  String get workspaceId => _workspace.id;

  @override
  String get displayTitle {
    final runtimeTitle = _title.trim();
    if (runtimeTitle.isEmpty || runtimeTitle == 'Terminal') {
      return _tab.title;
    }
    return runtimeTitle;
  }

  @override
  bool get isRunning => _running;

  @override
  bool get isStarting => _starting;

  @override
  String? get errorMessage => _errorMessage;

  _XtermTerminalSessionHandle sync({
    required Workspace workspace,
    required TerminalTabRecord tab,
  }) {
    final metadataChanged =
        _workspace.id != workspace.id ||
        _workspace.path != workspace.path ||
        _tab.id != tab.id ||
        _tab.title != tab.title;
    _workspace = workspace;
    _tab = tab;
    if (metadataChanged) {
      // sync() is invoked from build(); defer the notification so listening
      // AnimatedBuilders are not marked dirty during the build phase.
      scheduleMicrotask(() {
        if (!_disposed) {
          notifyListeners();
        }
      });
    }
    return this;
  }

  @override
  Future<void> ensureStarted() async {
    if (_started || _starting) {
      return;
    }
    _starting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
        throw UnsupportedError('Terminal sessions require the macOS PTY path.');
      }
      await _startMacOsPtySession();
      _started = true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final command = _changeDirectoryCommand(_workspace.path);
      if (command.isNotEmpty) {
        _macOsPtySession?.writeBytes(utf8.encode(command));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      _macOsPtySession?.writeBytes(utf8.encode('clear\n'));
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  @override
  Future<void> restart() async {
    _errorMessage = null;
    _started = false;
    _starting = false;
    _running = false;
    notifyListeners();
    await _stopMacOsPtySession();
    await ensureStarted();
  }

  @override
  Widget buildView({Key? key, bool autofocus = false}) {
    return xterm.TerminalView(
      _terminal,
      key: key,
      controller: _terminalController,
      autofocus: autofocus,
      theme: _aleraXtermTheme,
      textStyle: xterm.TerminalStyle(
        fontSize: 13,
        height: 1.3,
        fontFamily: GoogleFonts.jetBrainsMono().fontFamily ?? 'monospace',
        fontFamilyFallback: _terminalFontFallback,
      ),
      padding: const EdgeInsets.all(AleraTokens.space12),
      cursorType: xterm.TerminalCursorType.block,
      backgroundOpacity: 1,
    );
  }

  void _handleTitleChanged(String title) {
    _title = title;
    notifyListeners();
  }

  void _handleTerminalInput(String data) {
    _macOsPtySession?.writeBytes(utf8.encode(data));
  }

  void _handleTerminalResize(
    int width,
    int height,
    int pixelWidth,
    int pixelHeight,
  ) {
    _pendingPtySize = _TerminalPtySize(
      cols: width,
      rows: height,
      cellWidthPx: pixelWidth,
      cellHeightPx: pixelHeight,
    );
    _pendingPtyResizeTimer ??= Timer(
      _ptyResizeDebounceDuration,
      _flushPendingPtyResize,
    );
  }

  void _flushPendingPtyResize() {
    _pendingPtyResizeTimer = null;
    final size = _pendingPtySize;
    _pendingPtySize = null;
    final session = _macOsPtySession;
    if (_disposed || size == null || session == null) {
      return;
    }
    session.resize(size.cols, size.rows, size.cellWidthPx, size.cellHeightPx);
  }

  Future<void> _startMacOsPtySession() async {
    final launches = _terminalShellLaunches();
    Object? lastError;
    for (final launch in launches) {
      final session = _MacOsPtySession(
        onOutput: _ptyOutputController.add,
        onExit: (exitCode) {
          _running = false;
          _writeToTerminal('\n[process exited: $exitCode]\n');
          notifyListeners();
        },
        onError: (error) {
          _writeToTerminal('\n[terminal error: $error]\n');
        },
      );
      try {
        await session.start(
          launch: launch,
          cols: _terminal.viewWidth,
          rows: _terminal.viewHeight,
        );
        _macOsPtySession = session;
        _running = true;
        notifyListeners();
        final setupCommand = launch.setupCommand;
        if (setupCommand != null && setupCommand.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          session.writeBytes(utf8.encode(setupCommand));
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        return;
      } catch (error) {
        lastError = error;
        session.dispose();
      }
    }
    throw StateError('No macOS PTY shell could be started: $lastError');
  }

  xterm.Terminal _createTerminal() {
    final terminal = xterm.Terminal(
      maxLines: 10000,
      platform: _xtermTargetPlatform,
    );
    terminal.onTitleChange = _handleTitleChanged;
    terminal.onOutput = _handleTerminalInput;
    terminal.onResize = _handleTerminalResize;
    return terminal;
  }

  void _detachTerminal(xterm.Terminal terminal) {
    terminal.onTitleChange = null;
    terminal.onOutput = null;
    terminal.onResize = null;
  }

  void _handleTerminalOutput(String data) {
    _writeToTerminal(data);
  }

  void _writeToTerminal(String data) {
    if (data.isEmpty || _disposed) {
      return;
    }
    _terminal.write(data);
  }

  Future<void> _stopMacOsPtySession() async {
    _pendingPtyResizeTimer?.cancel();
    _pendingPtyResizeTimer = null;
    _pendingPtySize = null;
    final session = _macOsPtySession;
    _macOsPtySession = null;
    session?.dispose();
  }

  String _changeDirectoryCommand(String path) {
    if (path.trim().isEmpty) {
      return '';
    }
    final escaped = path.replaceAll("'", r"'\''");
    return "cd '$escaped'\n";
  }

  @override
  void dispose() {
    _disposed = true;
    _detachTerminal(_terminal);
    unawaited(_stopMacOsPtySession());
    unawaited(_decodedOutputSub.cancel());
    unawaited(_ptyOutputController.close());
    super.dispose();
  }
}

class _TerminalPtySize {
  const _TerminalPtySize({
    required this.cols,
    required this.rows,
    required this.cellWidthPx,
    required this.cellHeightPx,
  });

  final int cols;
  final int rows;
  final int cellWidthPx;
  final int cellHeightPx;
}

const Duration _ptyResizeDebounceDuration = Duration(milliseconds: 150);

Map<String, String> _terminalPlatformEnvironment() {
  final environment = <String, String>{...ghosttyTerminalPlatformEnvironment()};
  environment.remove('NO_COLOR');
  return environment;
}

List<GhosttyTerminalShellLaunch> _terminalShellLaunches() {
  final platformEnvironment = _terminalPlatformEnvironment();
  final launches = <GhosttyTerminalShellLaunch>[
    ...ghosttyTerminalShellLaunches(
      profile: GhosttyTerminalShellProfile.userShell,
      platformEnvironment: platformEnvironment,
    ),
    ...ghosttyTerminalShellLaunches(
      profile: GhosttyTerminalShellProfile.cleanZsh,
      platformEnvironment: platformEnvironment,
    ),
    ...ghosttyTerminalShellLaunches(
      profile: GhosttyTerminalShellProfile.auto,
      platformEnvironment: platformEnvironment,
    ),
  ];
  final seen = <String>{};
  return launches
      .where((launch) {
        final key = '${launch.shell}\u0000${launch.arguments.join('\u0000')}';
        return seen.add(key);
      })
      .toList(growable: false);
}

final xterm.TerminalTargetPlatform _xtermTargetPlatform =
    switch (defaultTargetPlatform) {
      TargetPlatform.android => xterm.TerminalTargetPlatform.android,
      TargetPlatform.iOS => xterm.TerminalTargetPlatform.ios,
      TargetPlatform.fuchsia => xterm.TerminalTargetPlatform.fuchsia,
      TargetPlatform.linux => xterm.TerminalTargetPlatform.linux,
      TargetPlatform.macOS => xterm.TerminalTargetPlatform.macos,
      TargetPlatform.windows => xterm.TerminalTargetPlatform.windows,
    };

const List<String> _terminalFontFallback = <String>[
  'SF Mono',
  'Menlo',
  'Monaco',
  'Cascadia Mono',
  'Consolas',
  'DejaVu Sans Mono',
  'Liberation Mono',
  'Symbols Nerd Font Mono',
  'MesloLGS Nerd Font',
  'JetBrainsMono Nerd Font',
  'Hack Nerd Font',
  'Apple Symbols',
  'Noto Color Emoji',
  'Noto Sans Symbols',
  'monospace',
];

const xterm.TerminalTheme _aleraXtermTheme = xterm.TerminalTheme(
  cursor: AleraTokens.accent,
  selection: AleraTokens.accentSubtle,
  foreground: AleraTokens.foreground,
  background: AleraTokens.bg,
  black: AleraTokens.foregroundFaint,
  red: AleraTokens.error,
  green: AleraTokens.success,
  yellow: AleraTokens.warning,
  blue: AleraTokens.info,
  magenta: AleraTokens.accent,
  cyan: AleraTokens.info,
  white: AleraTokens.foreground,
  brightBlack: AleraTokens.foregroundMuted,
  brightRed: AleraTokens.error,
  brightGreen: AleraTokens.success,
  brightYellow: AleraTokens.warning,
  brightBlue: AleraTokens.info,
  brightMagenta: AleraTokens.accent,
  brightCyan: AleraTokens.info,
  brightWhite: AleraTokens.foreground,
  searchHitBackground: AleraTokens.surfaceElevated,
  searchHitBackgroundCurrent: AleraTokens.accentSubtle,
  searchHitForeground: AleraTokens.foreground,
);

class GhosttyTerminalRuntime implements TerminalRuntime {
  final Map<String, _GhosttyTerminalSessionHandle> _sessions =
      <String, _GhosttyTerminalSessionHandle>{};

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required TerminalTabRecord tab,
  }) {
    return _sessions
        .putIfAbsent(tab.id, () {
          return _GhosttyTerminalSessionHandle(workspace: workspace, tab: tab);
        })
        .sync(workspace: workspace, tab: tab);
  }

  @override
  void closeTab(String tabId) {
    _sessions.remove(tabId)?.dispose();
  }

  @override
  void closeWorkspace(String workspaceId) {
    final removed = _sessions.entries
        .where((entry) => entry.value.workspaceId == workspaceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final tabId in removed) {
      _sessions.remove(tabId)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}

class _GhosttyTerminalSessionHandle extends TerminalSessionHandle {
  _GhosttyTerminalSessionHandle({
    required Workspace workspace,
    required TerminalTabRecord tab,
  }) : _workspace = workspace,
       _tab = tab {
    _controller.onTitleChangedData = _handleTitleChanged;
  }

  Workspace _workspace;
  TerminalTabRecord _tab;
  final GhosttyTerminalController _controller = GhosttyTerminalController();
  _MacOsPtySession? _macOsPtySession;

  bool _starting = false;
  bool _started = false;
  bool _disposed = false;
  String? _errorMessage;

  @override
  String get tabId => _tab.id;

  @override
  String get workspaceId => _workspace.id;

  @override
  String get displayTitle {
    final runtimeTitle = _controller.title.trim();
    if (runtimeTitle.isEmpty ||
        runtimeTitle == 'Terminal' ||
        runtimeTitle == 'Terminal (Web)') {
      return _tab.title;
    }
    return runtimeTitle;
  }

  @override
  bool get isRunning => _controller.isRunning;

  @override
  bool get isStarting => _starting;

  @override
  String? get errorMessage => _errorMessage;

  _GhosttyTerminalSessionHandle sync({
    required Workspace workspace,
    required TerminalTabRecord tab,
  }) {
    final metadataChanged =
        _workspace.id != workspace.id ||
        _workspace.path != workspace.path ||
        _tab.id != tab.id ||
        _tab.title != tab.title;
    _workspace = workspace;
    _tab = tab;
    if (metadataChanged) {
      // sync() is invoked from build(); defer the notification so listening
      // AnimatedBuilders are not marked dirty during the build phase.
      scheduleMicrotask(() {
        if (!_disposed) {
          notifyListeners();
        }
      });
    }
    return this;
  }

  @override
  Future<void> ensureStarted() async {
    if (_started || _starting) {
      return;
    }
    _starting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (kIsWeb) {
        await _controller.start();
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        await _startMacOsPtySession();
      } else {
        final launch = await _controller.startShellProfile(
          profile: GhosttyTerminalShellProfile.auto,
          platformEnvironment: _terminalPlatformEnvironment(),
        );
        if (launch == null) {
          await _controller.start(
            environment: ghosttyTerminalShellEnvironment(
              platformEnvironment: _terminalPlatformEnvironment(),
            ),
          );
        }
      }
      _started = true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final command = _changeDirectoryCommand(_workspace.path);
      if (command.isNotEmpty) {
        _controller.write(command);
      }
      if (!_isWindows) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        _controller.write('clear\n');
      }
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  @override
  Future<void> restart() async {
    _errorMessage = null;
    _started = false;
    _starting = false;
    notifyListeners();
    await _controller.stop();
    await _stopMacOsPtySession();
    await ensureStarted();
  }

  @override
  Widget buildView({Key? key, bool autofocus = false}) {
    return GhosttyTerminalView(
      key: key,
      controller: _controller,
      autofocus: autofocus,
      showVerticalScrollbar: true,
      autoFollowOnActivity: true,
      backgroundColor: AleraTokens.bg,
      foregroundColor: AleraTokens.foreground,
      chromeColor: AleraTokens.surface,
      fontSize: 13,
      lineHeight: 1.3,
      fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
      fontFamilyFallback: const <String>['Menlo', 'monospace'],
      padding: const EdgeInsets.all(AleraTokens.space12),
      cursorColor: AleraTokens.accent,
      selectionColor: AleraTokens.accentSubtle,
      hyperlinkColor: AleraTokens.info,
      scrollbarThumbColor: AleraTokens.foregroundFaint,
      scrollbarTrackColor: AleraTokens.surfaceElevated,
    );
  }

  void _handleTitleChanged() {
    notifyListeners();
  }

  Future<void> _startMacOsPtySession() async {
    final launches = _terminalShellLaunches();
    Object? lastError;
    for (final launch in launches) {
      final session = _MacOsPtySession(
        onOutput: _controller.appendOutputBytes,
        onExit: (exitCode) {
          _controller.setSessionRunning(false);
          _controller.appendDebugOutput('\n[process exited: $exitCode]\n');
        },
        onError: (error) {
          _controller.appendDebugOutput('\n[terminal error: $error]\n');
        },
      );
      try {
        await session.start(
          launch: launch,
          cols: _controller.cols,
          rows: _controller.rows,
        );
        _macOsPtySession = session;
        _controller.attachExternalTransport(
          writeBytes: session.writeBytes,
          onResize: session.resize,
          launch: launch,
        );
        final setupCommand = launch.setupCommand;
        if (setupCommand != null && setupCommand.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          _controller.write(setupCommand);
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        return;
      } catch (error) {
        lastError = error;
        session.dispose();
      }
    }
    throw StateError('No macOS PTY shell could be started: $lastError');
  }

  Future<void> _stopMacOsPtySession() async {
    final session = _macOsPtySession;
    _macOsPtySession = null;
    _controller.detachExternalTransport();
    session?.dispose();
  }

  String _changeDirectoryCommand(String path) {
    if (path.trim().isEmpty) {
      return '';
    }
    if (_isWindows) {
      return 'cd /d "${path.replaceAll('"', '""')}"\r\n';
    }
    final escaped = path.replaceAll("'", r"'\''");
    return "cd '$escaped'\n";
  }

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void dispose() {
    _disposed = true;
    _controller.onTitleChangedData = null;
    unawaited(_stopMacOsPtySession());
    _controller.dispose();
    super.dispose();
  }
}

typedef _ReadNative =
    ffi.IntPtr Function(
      ffi.Int32 fd,
      ffi.Pointer<ffi.Uint8> buf,
      ffi.UintPtr nbyte,
    );
typedef _ReadDart = int Function(int fd, ffi.Pointer<ffi.Uint8> buf, int nbyte);
final ffi.DynamicLibrary _libc = ffi.DynamicLibrary.process();
final _ReadDart _posixRead = _libc.lookupFunction<_ReadNative, _ReadDart>(
  'read',
);

// macOS exposes errno through `int* __error(void)`.
typedef _ErrnoLocationNative = ffi.Pointer<ffi.Int32> Function();
typedef _ErrnoLocationDart = ffi.Pointer<ffi.Int32> Function();
final _ErrnoLocationDart _errnoLocation = _libc
    .lookupFunction<_ErrnoLocationNative, _ErrnoLocationDart>('__error');

int _currentErrno() => _errnoLocation().value;

/// `EINTR` (interrupted system call) on macOS.
const int _eintr = 4;

const int _readChunkSize = 4096;

class _MacOsPtySession {
  _MacOsPtySession({
    required this.onOutput,
    required this.onExit,
    required this.onError,
  });

  final void Function(Uint8List data) onOutput;
  final void Function(int exitCode) onExit;
  final void Function(Object error) onError;

  PortablePty? _pty;
  ReceivePort? _readPort;
  StreamSubscription<Object?>? _readSub;
  Isolate? _readIsolate;
  bool _closed = false;

  Future<void> start({
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  }) async {
    final pty = PortablePty.open(rows: rows, cols: cols);
    _pty = pty;
    try {
      pty.spawn(
        launch.shell,
        args: launch.arguments,
        environment: launch.environment,
      );
      _readPort = ReceivePort();
      _readSub = _readPort!.listen(_handleReadMessage);
      _readIsolate = await Isolate.spawn<List<Object?>>(
        _macOsPtyReadIsolate,
        <Object?>[pty.masterFd, _readPort!.sendPort],
        debugName: 'alera-macos-pty-reader',
      );
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  bool writeBytes(List<int> bytes) {
    final pty = _pty;
    if (_closed || pty == null || bytes.isEmpty) {
      return false;
    }
    try {
      return pty.writeBytes(Uint8List.fromList(bytes)) > 0;
    } catch (error) {
      onError(error);
      return false;
    }
  }

  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {
    final pty = _pty;
    if (_closed || pty == null) {
      return;
    }
    try {
      pty.resize(rows: rows, cols: cols);
    } catch (error) {
      onError(error);
    }
  }

  void _handleReadMessage(Object? message) {
    if (_closed) {
      return;
    }
    if (message is Uint8List) {
      onOutput(message);
      return;
    }
    if (message is Map<Object?, Object?>) {
      final type = message['type'];
      if (type == 'error') {
        onError(message['error'] ?? 'Unknown PTY read error');
      }
      if (type == 'done' || type == 'error') {
        final pty = _pty;
        _handleExit(pty?.tryWait() ?? 0);
      }
    }
  }

  void _handleExit(int exitCode) {
    if (_closed) {
      return;
    }
    onExit(exitCode);
    dispose();
  }

  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _readSub?.cancel();
    _readSub = null;
    _readPort?.close();
    _readPort = null;
    _readIsolate?.kill(priority: Isolate.immediate);
    _readIsolate = null;
    final pty = _pty;
    _pty = null;
    if (pty == null) {
      return;
    }
    try {
      if (pty.tryWait() == null) {
        pty.kill();
      }
    } catch (_) {
      // The child can exit between tryWait and kill.
    } finally {
      pty.close();
    }
  }
}

void _macOsPtyReadIsolate(List<Object?> args) {
  final fd = args[0]! as int;
  final sendPort = args[1]! as SendPort;
  final buffer = calloc<ffi.Uint8>(_readChunkSize);
  try {
    while (true) {
      final byteCount = _posixRead(fd, buffer, _readChunkSize);
      if (byteCount > 0) {
        sendPort.send(Uint8List.fromList(buffer.asTypedList(byteCount)));
        continue;
      }
      if (byteCount < 0 && _currentErrno() == _eintr) {
        // Interrupted by a signal; the child is still alive, keep reading
        // instead of tearing the session down.
        continue;
      }
      sendPort.send(const <Object?, Object?>{'type': 'done'});
      break;
    }
  } catch (error) {
    sendPort.send(<Object?, Object?>{
      'type': 'error',
      'error': error.toString(),
    });
  } finally {
    calloc.free(buffer);
  }
}
