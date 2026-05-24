// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
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

abstract interface class TerminalPtySessionFactory {
  TerminalPtySession create();
}

abstract interface class TerminalPtySession {
  Stream<TerminalPtySessionEvent> get events;

  Future<void> start({
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  });

  bool writeBytes(List<int> bytes);

  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx);

  void dispose();
}

sealed class TerminalPtySessionEvent {
  const TerminalPtySessionEvent();
}

final class TerminalPtyOutputEvent extends TerminalPtySessionEvent {
  const TerminalPtyOutputEvent(this.data);

  final Uint8List data;
}

final class TerminalPtyExitEvent extends TerminalPtySessionEvent {
  const TerminalPtyExitEvent(this.exitCode);

  final int exitCode;
}

final class TerminalPtyErrorEvent extends TerminalPtySessionEvent {
  const TerminalPtyErrorEvent(this.error);

  final Object error;
}

class GhosttyTerminalPtySessionFactory implements TerminalPtySessionFactory {
  const GhosttyTerminalPtySessionFactory();

  @override
  TerminalPtySession create() {
    return _GhosttyTerminalPtySessionAdapter();
  }
}

class _GhosttyTerminalPtySessionAdapter implements TerminalPtySession {
  final StreamController<TerminalPtySessionEvent> _events =
      StreamController<TerminalPtySessionEvent>.broadcast();
  GhosttyTerminalPtySession? _session;
  StreamSubscription<GhosttyTerminalPtySessionEvent>? _sessionSub;
  bool _disposed = false;

  @override
  Stream<TerminalPtySessionEvent> get events => _events.stream;

  @override
  Future<void> start({
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  }) async {
    if (_disposed) {
      throw StateError('PTY session is disposed.');
    }
    final session = GhosttyTerminalPtySession(
      config: GhosttyTerminalPtySessionConfig(rows: rows, cols: cols),
    );
    _session = session;
    _sessionSub = session.events.listen(_handleGhosttyEvent);
    try {
      session.spawn(
        launch.shell,
        args: launch.arguments,
        environment: launch.environment,
      );
    } catch (_) {
      unawaited(_sessionSub?.cancel());
      _sessionSub = null;
      _session = null;
      session.close();
      rethrow;
    }
  }

  void _handleGhosttyEvent(GhosttyTerminalPtySessionEvent event) {
    if (_disposed) {
      return;
    }
    switch (event) {
      case GhosttyTerminalPtyOutputEvent(:final data):
        _events.add(TerminalPtyOutputEvent(data));
      case GhosttyTerminalPtyExitEvent(:final exitCode):
        _events.add(TerminalPtyExitEvent(exitCode));
      case GhosttyTerminalPtyErrorEvent(:final error):
        _events.add(TerminalPtyErrorEvent(error));
      case GhosttyTerminalPtyStateChangeEvent():
        break;
    }
  }

  @override
  bool writeBytes(List<int> bytes) {
    final session = _session;
    if (_disposed || session == null || bytes.isEmpty) {
      return false;
    }
    return session.writeBytes(Uint8List.fromList(bytes)) > 0;
  }

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {
    if (_disposed) {
      return;
    }
    _session?.resize(rows: rows, cols: cols);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_sessionSub?.cancel());
    _sessionSub = null;
    _session?.close();
    _session = null;
    unawaited(_events.close());
  }
}

class XtermTerminalRuntime implements TerminalRuntime {
  XtermTerminalRuntime({TerminalPtySessionFactory? ptySessionFactory})
    : _ptySessionFactory =
          ptySessionFactory ?? const GhosttyTerminalPtySessionFactory();

  final TerminalPtySessionFactory _ptySessionFactory;
  final Map<String, _XtermTerminalSessionHandle> _sessions =
      <String, _XtermTerminalSessionHandle>{};

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required TerminalTabRecord tab,
  }) {
    return _sessions
        .putIfAbsent(tab.id, () {
          return _XtermTerminalSessionHandle(
            workspace: workspace,
            tab: tab,
            ptySessionFactory: _ptySessionFactory,
          );
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
    required TerminalPtySessionFactory ptySessionFactory,
  }) : _workspace = workspace,
       _tab = tab,
       _ptySessionFactory = ptySessionFactory {
    _terminal = _createTerminal();
    _decodedOutputSub = _ptyOutputController.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_handleTerminalOutput);
  }

  Workspace _workspace;
  TerminalTabRecord _tab;
  final TerminalPtySessionFactory _ptySessionFactory;
  late xterm.Terminal _terminal;
  final xterm.TerminalController _terminalController =
      xterm.TerminalController();
  final StreamController<List<int>> _ptyOutputController =
      StreamController<List<int>>();
  late final StreamSubscription<String> _decodedOutputSub;
  TerminalPtySession? _ptySession;
  StreamSubscription<TerminalPtySessionEvent>? _ptySessionSub;
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
      if (!_isSupportedNativeDesktopTerminalPlatform) {
        throw UnsupportedError(
          'Terminal sessions require a native desktop PTY path.',
        );
      }
      await _startPtySession();
      _started = true;
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
    await _stopPtySession();
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
    _ptySession?.writeBytes(utf8.encode(data));
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
    final session = _ptySession;
    if (_disposed || size == null || session == null) {
      return;
    }
    session.resize(size.cols, size.rows, size.cellWidthPx, size.cellHeightPx);
  }

  Future<void> _startPtySession() async {
    final launches = _terminalShellLaunches();
    Object? lastError;
    for (final launch in launches) {
      final session = _ptySessionFactory.create();
      final sub = session.events.listen(_handlePtySessionEvent);
      try {
        final workspaceLaunch = _launchInWorkingDirectory(
          launch,
          _workspace.path,
        );
        await session.start(
          launch: workspaceLaunch,
          cols: _terminal.viewWidth,
          rows: _terminal.viewHeight,
        );
        _ptySession = session;
        _ptySessionSub = sub;
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
        unawaited(sub.cancel());
        session.dispose();
      }
    }
    throw StateError('No desktop PTY shell could be started: $lastError');
  }

  void _handlePtySessionEvent(TerminalPtySessionEvent event) {
    switch (event) {
      case TerminalPtyOutputEvent(:final data):
        _ptyOutputController.add(data);
      case TerminalPtyExitEvent(:final exitCode):
        _running = false;
        _writeToTerminal('\n[process exited: $exitCode]\n');
        notifyListeners();
      case TerminalPtyErrorEvent(:final error):
        _writeToTerminal('\n[terminal error: $error]\n');
    }
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

  Future<void> _stopPtySession() async {
    _pendingPtyResizeTimer?.cancel();
    _pendingPtyResizeTimer = null;
    _pendingPtySize = null;
    final sub = _ptySessionSub;
    _ptySessionSub = null;
    await sub?.cancel();
    final session = _ptySession;
    _ptySession = null;
    session?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _detachTerminal(_terminal);
    unawaited(_stopPtySession());
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

GhosttyTerminalShellLaunch _launchInWorkingDirectory(
  GhosttyTerminalShellLaunch launch,
  String workingDirectory,
) {
  if (workingDirectory.trim().isEmpty) {
    return launch;
  }
  if (_isWindowsCommandPromptLaunch(launch)) {
    return GhosttyTerminalShellLaunch(
      label: launch.label,
      shell: launch.shell,
      arguments: <String>[
        ...launch.arguments,
        '/d',
        '/s',
        '/k',
        'cd /d ${_cmdQuote(workingDirectory)}',
      ],
      environment: launch.environment,
      setupCommand: launch.setupCommand,
    );
  }
  final execCommand = StringBuffer(
    'cd ${_shQuote(workingDirectory)} || true; exec ',
  )..write(_shQuote(launch.shell));
  for (final argument in launch.arguments) {
    execCommand
      ..write(' ')
      ..write(_shQuote(argument));
  }
  return GhosttyTerminalShellLaunch(
    label: launch.label,
    shell: '/bin/sh',
    arguments: <String>['-c', execCommand.toString()],
    environment: launch.environment,
    setupCommand: launch.setupCommand,
  );
}

@visibleForTesting
GhosttyTerminalShellLaunch launchInWorkingDirectoryForTesting(
  GhosttyTerminalShellLaunch launch,
  String workingDirectory,
) {
  return _launchInWorkingDirectory(launch, workingDirectory);
}

bool _isWindowsCommandPromptLaunch(GhosttyTerminalShellLaunch launch) {
  final executable = launch.shell.replaceAll(r'\', '/').split('/').last;
  return executable.toLowerCase() == 'cmd.exe';
}

String _cmdQuote(String value) {
  return '"${value.replaceAll('"', '""')}"';
}

String _shQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

bool get _isSupportedNativeDesktopTerminalPlatform {
  if (kIsWeb) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };
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
