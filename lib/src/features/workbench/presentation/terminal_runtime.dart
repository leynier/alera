// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/presentation/terminal_link_resolver.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  });

  /// Moves keyboard focus to this terminal's text input so subsequent
  /// keypresses are routed to its PTY instead of any sidebar control.
  void requestFocus();
}

abstract interface class TerminalRuntime {
  Stream<TerminalRuntimeExitEvent> get exits;

  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  });

  void closeTab(String tabId);

  void closeWorkspace(String workspaceId);

  void dispose();
}

final class TerminalRuntimeExitEvent {
  const TerminalRuntimeExitEvent({
    required this.workspaceId,
    required this.tabId,
    required this.exitCode,
  });

  final String workspaceId;
  final String tabId;
  final int exitCode;
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

class DefaultTerminalPtySessionFactory implements TerminalPtySessionFactory {
  const DefaultTerminalPtySessionFactory();

  @override
  TerminalPtySession create() {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      return _PosixPortablePtySessionAdapter();
    }
    return _GhosttyTerminalPtySessionAdapter();
  }
}

class _PosixPortablePtySessionAdapter implements TerminalPtySession {
  final StreamController<TerminalPtySessionEvent> _events =
      StreamController<TerminalPtySessionEvent>.broadcast();
  PortablePty? _pty;
  ReceivePort? _readPort;
  StreamSubscription<Object?>? _readSub;
  Isolate? _readIsolate;
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
        _posixPtyReadIsolate,
        <Object?>[pty.masterFd, _readPort!.sendPort],
        debugName: 'alera-posix-pty-reader',
      );
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  @override
  bool writeBytes(List<int> bytes) {
    final pty = _pty;
    if (_disposed || pty == null || bytes.isEmpty) {
      return false;
    }
    return _writePtyBytes(bytes: bytes, write: pty.writeBytes, events: _events);
  }

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {
    final pty = _pty;
    if (_disposed || pty == null) {
      return;
    }
    _resizePty(
      rows: rows,
      cols: cols,
      resize: ({required rows, required cols}) =>
          pty.resize(rows: rows, cols: cols),
      events: _events,
    );
  }

  void _handleReadMessage(Object? message) {
    if (_disposed) {
      return;
    }
    if (message is Uint8List) {
      _events.add(TerminalPtyOutputEvent(message));
      return;
    }
    if (message is Map<Object?, Object?>) {
      final type = message['type'];
      if (type == 'error') {
        _events.add(
          TerminalPtyErrorEvent(message['error'] ?? 'Unknown PTY read error'),
        );
      }
      if (type == 'done' || type == 'error') {
        _handleExit(_pty?.tryWait() ?? 0);
      }
    }
  }

  void _handleExit(int exitCode) {
    if (_disposed) {
      return;
    }
    _events.add(TerminalPtyExitEvent(exitCode));
    dispose();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_readSub?.cancel());
    _readSub = null;
    _readPort?.close();
    _readPort = null;
    _readIsolate?.kill(priority: Isolate.immediate);
    _readIsolate = null;
    final pty = _pty;
    _pty = null;
    if (pty != null) {
      try {
        if (pty.tryWait() == null) {
          try {
            pty.kill();
          } catch (_) {
            // The child can exit between tryWait and kill.
          }
        }
      } finally {
        pty.close();
      }
    }
    unawaited(_events.close());
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

@visibleForTesting
TerminalPtySession createPosixPtySessionForTesting() {
  return _PosixPortablePtySessionAdapter();
}

@visibleForTesting
TerminalPtySession createGhosttyPtySessionForTesting() {
  return _GhosttyTerminalPtySessionAdapter();
}

@visibleForTesting
void handlePosixReadMessageForTesting(
  TerminalPtySession session,
  Object? message,
) {
  (session as _PosixPortablePtySessionAdapter)._handleReadMessage(message);
}

@visibleForTesting
void handleGhosttyEventForTesting(
  TerminalPtySession session,
  GhosttyTerminalPtySessionEvent event,
) {
  (session as _GhosttyTerminalPtySessionAdapter)._handleGhosttyEvent(event);
}

class XtermTerminalRuntime implements TerminalRuntime {
  XtermTerminalRuntime({
    TerminalPtySessionFactory? ptySessionFactory,
    TerminalSettings? initialSettings,
    ExternalUriLauncher? externalUriLauncher,
    List<GhosttyTerminalShellLaunch> Function()? shellLaunchesBuilder,
  }) : _settings = initialSettings ?? TerminalSettings.defaults,
       _externalUriLauncher =
           externalUriLauncher ?? UrlLauncherExternalUriLauncher(),
       _ptySessionFactory =
           ptySessionFactory ?? const DefaultTerminalPtySessionFactory(),
       _shellLaunchesBuilder = shellLaunchesBuilder ?? _terminalShellLaunches;

  final TerminalPtySessionFactory _ptySessionFactory;
  final ExternalUriLauncher _externalUriLauncher;
  final List<GhosttyTerminalShellLaunch> Function() _shellLaunchesBuilder;
  TerminalSettings _settings;
  final StreamController<TerminalRuntimeExitEvent> _exitController =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final Map<String, _XtermTerminalSessionHandle> _sessions =
      <String, _XtermTerminalSessionHandle>{};

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exitController.stream;

  void updateSettings(TerminalSettings settings) {
    _settings = settings;
    for (final session in _sessions.values) {
      session.applySettings(settings);
    }
  }

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return _sessions
        .putIfAbsent(tab.id, () {
          return _XtermTerminalSessionHandle(
            workspace: workspace,
            tab: tab,
            ptySessionFactory: _ptySessionFactory,
            settings: _settings,
            externalUriLauncher: _externalUriLauncher,
            shellLaunchesBuilder: _shellLaunchesBuilder,
            onExit: _handleSessionExit,
          );
        })
        .sync(workspace: workspace, tab: tab);
  }

  void _handleSessionExit(TerminalRuntimeExitEvent event) {
    if (!_exitController.isClosed) {
      _exitController.add(event);
    }
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
    unawaited(_exitController.close());
  }
}

class _XtermTerminalSessionHandle extends TerminalSessionHandle {
  _XtermTerminalSessionHandle({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
    required TerminalPtySessionFactory ptySessionFactory,
    required TerminalSettings settings,
    required ExternalUriLauncher externalUriLauncher,
    required List<GhosttyTerminalShellLaunch> Function() shellLaunchesBuilder,
    required void Function(TerminalRuntimeExitEvent event) onExit,
  }) : _workspace = workspace,
       _tab = tab,
       _ptySessionFactory = ptySessionFactory,
       _settings = settings,
       _externalUriLauncher = externalUriLauncher,
       _shellLaunchesBuilder = shellLaunchesBuilder,
       _onExit = onExit {
    _terminal = _createTerminal();
    _osc8LinkTracker = Osc8TerminalLinkTracker(terminal: _terminal);
    _attachTerminal(_terminal);
    _decodedOutputSub = _ptyOutputController.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_handleTerminalOutput);
  }

  Workspace _workspace;
  WorkspaceTabRecord _tab;
  final TerminalPtySessionFactory _ptySessionFactory;
  final ExternalUriLauncher _externalUriLauncher;
  final List<GhosttyTerminalShellLaunch> Function() _shellLaunchesBuilder;
  final void Function(TerminalRuntimeExitEvent event) _onExit;
  TerminalSettings _settings;
  late xterm.Terminal _terminal;
  late final Osc8TerminalLinkTracker _osc8LinkTracker;
  final GlobalKey<xterm.TerminalViewState> _terminalViewKey =
      GlobalKey<xterm.TerminalViewState>();
  final xterm.TerminalController _terminalController =
      xterm.TerminalController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'TerminalSession');
  final StreamController<List<int>> _ptyOutputController =
      StreamController<List<int>>();
  late final StreamSubscription<String> _decodedOutputSub;
  TerminalPtySession? _ptySession;
  StreamSubscription<TerminalPtySessionEvent>? _ptySessionSub;
  Timer? _pendingPtyResizeTimer;
  _TerminalPtySize? _pendingPtySize;
  int _ptyGeneration = 0;
  int? _activePtyGeneration;
  final Set<int> _exitedPtyGenerations = <int>{};
  final Set<int> _suppressedExitPtyGenerations = <int>{};

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
    if (_tab.hasManualTitle) {
      return _tab.title;
    }
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
    required WorkspaceTabRecord tab,
  }) {
    final metadataChanged =
        _workspace.id != workspace.id ||
        _workspace.path != workspace.path ||
        _tab.id != tab.id ||
        _tab.title != tab.title ||
        _tab.hasManualTitle != tab.hasManualTitle;
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

  void applySettings(TerminalSettings settings) {
    _settings = settings;
    notifyListeners();
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
    await _stopPtySession(suppressExit: true);
    await ensureStarted();
  }

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return _InteractiveTerminalView(
      key: key,
      session: this,
      autofocus: autofocus,
      onKeyEvent: onKeyEvent,
    );
  }

  xterm.TerminalView _buildTerminalView({
    required bool autofocus,
    FocusOnKeyEventCallback? onKeyEvent,
    required MouseCursor mouseCursor,
    void Function(TapUpDetails details, xterm.CellOffset offset)? onTapUp,
  }) {
    return xterm.TerminalView(
      _terminal,
      key: _terminalViewKey,
      controller: _terminalController,
      focusNode: _focusNode,
      autofocus: autofocus,
      onTapUp: onTapUp,
      onKeyEvent: onKeyEvent,
      mouseCursor: mouseCursor,
      theme: _resolveXtermTheme(_settings),
      textStyle: xterm.TerminalStyle(
        fontSize: _settings.fontSize,
        fontWeight: _settings.fontWeight,
        height: _settings.lineHeight,
        fontFamily: _resolveTerminalFontFamily(_settings.fontFamily),
        fontFamilyFallback: _terminalFontFallback,
      ),
      padding: EdgeInsets.fromLTRB(
        _settings.paddingX,
        _settings.paddingY,
        _settings.paddingX,
        _settings.paddingY,
      ),
      cursorType: _settings.cursorShape.toXtermCursorType(),
      cursorBlink: _settings.cursorBlink,
      backgroundOpacity: _settings.backgroundOpacity,
    );
  }

  TerminalLinkRange? _linkAt(xterm.CellOffset offset) {
    return resolveTerminalLinkAt(
      terminal: _terminal,
      offset: offset,
      osc8Tracker: _osc8LinkTracker,
    );
  }

  Future<void> _openLink(Uri uri) {
    return _externalUriLauncher.open(uri);
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
    final launches = _shellLaunchesBuilder();
    Object? lastError;
    for (final launch in launches) {
      final session = _ptySessionFactory.create();
      final generation = ++_ptyGeneration;
      final sub = session.events.listen(
        (event) => _handlePtySessionEvent(event, generation),
      );
      _ptySession = session;
      _ptySessionSub = sub;
      _activePtyGeneration = generation;
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
        _running = true;
        _prunePtyGenerationState();
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
        _suppressedExitPtyGenerations.add(generation);
        if (_activePtyGeneration == generation) {
          _activePtyGeneration = null;
        }
        if (identical(_ptySession, session)) {
          _ptySession = null;
        }
        if (identical(_ptySessionSub, sub)) {
          _ptySessionSub = null;
        }
        unawaited(sub.cancel());
        session.dispose();
        _prunePtyGenerationState();
      }
    }
    throw StateError('No desktop PTY shell could be started: $lastError');
  }

  void _handlePtySessionEvent(TerminalPtySessionEvent event, int generation) {
    if (_disposed || generation != _activePtyGeneration) {
      return;
    }
    switch (event) {
      case TerminalPtyOutputEvent(:final data):
        _ptyOutputController.add(data);
      case TerminalPtyExitEvent(:final exitCode):
        _handlePtyExit(exitCode: exitCode, generation: generation);
      case TerminalPtyErrorEvent(:final error):
        _writeToTerminal('\n[terminal error: $error]\n');
    }
  }

  void _handlePtyExit({required int exitCode, required int generation}) {
    if (!_exitedPtyGenerations.add(generation)) {
      return;
    }
    _running = false;
    _writeToTerminal('\n[process exited: $exitCode]\n');
    notifyListeners();
    if (!_suppressedExitPtyGenerations.contains(generation)) {
      _onExit(
        TerminalRuntimeExitEvent(
          workspaceId: workspaceId,
          tabId: tabId,
          exitCode: exitCode,
        ),
      );
    }
    unawaited(_stopPtySession(suppressExit: true));
  }

  void _handlePrivateOsc(String code, List<String> args) {
    _osc8LinkTracker.handlePrivateOsc(code, args);
  }

  xterm.Terminal _createTerminal() {
    return xterm.Terminal(
      maxLines: _settings.scrollbackLines,
      platform: _xtermTargetPlatform,
      wordSeparators: _wordSeparatorsFromSettings(_settings.wordSeparators),
    );
  }

  void _attachTerminal(xterm.Terminal terminal) {
    terminal.onTitleChange = _handleTitleChanged;
    terminal.onOutput = _handleTerminalInput;
    terminal.onResize = _handleTerminalResize;
    terminal.onPrivateOSC = _handlePrivateOsc;
  }

  void _detachTerminal(xterm.Terminal terminal) {
    terminal.onTitleChange = null;
    terminal.onOutput = null;
    terminal.onResize = null;
    terminal.onPrivateOSC = null;
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

  Future<void> _stopPtySession({required bool suppressExit}) async {
    _pendingPtyResizeTimer?.cancel();
    _pendingPtyResizeTimer = null;
    _pendingPtySize = null;
    final generation = _activePtyGeneration;
    if (suppressExit && generation != null) {
      _suppressedExitPtyGenerations.add(generation);
    }
    if (_activePtyGeneration == generation) {
      _activePtyGeneration = null;
    }
    final sub = _ptySessionSub;
    _ptySessionSub = null;
    await sub?.cancel();
    final session = _ptySession;
    _ptySession = null;
    session?.dispose();
    _prunePtyGenerationState();
  }

  void _prunePtyGenerationState() {
    final active = _activePtyGeneration;
    _exitedPtyGenerations.removeWhere((generation) => generation != active);
    _suppressedExitPtyGenerations.removeWhere(
      (generation) => generation != active,
    );
  }

  @override
  void requestFocus() {
    // Defer to the next frame so the terminal view is mounted (e.g. after
    // switching workspaces) before we ask the FocusNode to claim focus.
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocusNow());
  }

  @override
  void dispose() {
    _disposed = true;
    _osc8LinkTracker.dispose();
    _detachTerminal(_terminal);
    unawaited(_stopPtySession(suppressExit: true));
    unawaited(_decodedOutputSub.cancel());
    unawaited(_ptyOutputController.close());
    _focusNode.dispose();
    super.dispose();
  }

  void _requestFocusNow() {
    if (_disposed || !_focusNode.canRequestFocus) {
      return;
    }
    _focusNode.requestFocus();
  }
}

class _InteractiveTerminalView extends StatefulWidget {
  const _InteractiveTerminalView({
    super.key,
    required this.session,
    required this.autofocus,
    this.onKeyEvent,
  });

  final _XtermTerminalSessionHandle session;
  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<_InteractiveTerminalView> createState() =>
      _InteractiveTerminalViewState();
}

class _InteractiveTerminalViewState extends State<_InteractiveTerminalView> {
  TerminalLinkRange? _hoveredLink;

  @override
  void didUpdateWidget(covariant _InteractiveTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _hoveredLink = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onExit: (_) => _setHoveredLink(null),
      onHover: _handleHover,
      child: widget.session._buildTerminalView(
        autofocus: widget.autofocus,
        onKeyEvent: widget.onKeyEvent,
        mouseCursor: _hoveredLink == null
            ? SystemMouseCursors.text
            : SystemMouseCursors.click,
        onTapUp: _handleTapUp,
      ),
    );
  }

  void _handleHover(PointerHoverEvent event) {
    final viewState = widget.session._terminalViewKey.currentState;
    if (viewState == null) {
      return;
    }
    final localPosition = viewState.renderTerminal.globalToLocal(
      event.position,
    );
    final offset = viewState.renderTerminal.getCellOffset(localPosition);
    _setHoveredLink(widget.session._linkAt(offset));
  }

  void _handleTapUp(TapUpDetails _, xterm.CellOffset offset) {
    if (!isTerminalLinkActivation()) {
      return;
    }
    final link = widget.session._linkAt(offset);
    if (link == null) {
      return;
    }
    unawaited(_openLink(link.uri));
  }

  Future<void> _openLink(Uri uri) async {
    try {
      await widget.session._openLink(uri);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open link: $uri')));
    }
  }

  void _setHoveredLink(TerminalLinkRange? link) {
    if (_hoveredLink == link) {
      return;
    }
    setState(() {
      _hoveredLink = link;
    });
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

@visibleForTesting
Map<String, String> terminalPlatformEnvironmentForTesting() {
  return _terminalPlatformEnvironment();
}

@visibleForTesting
List<GhosttyTerminalShellLaunch> terminalShellLaunchesForTesting() {
  return _terminalShellLaunches();
}

bool _isWindowsCommandPromptLaunch(GhosttyTerminalShellLaunch launch) {
  final executable = launch.shell.replaceAll(r'\', '/').split('/').last;
  return executable.toLowerCase() == 'cmd.exe';
}

String _cmdQuote(String value) {
  return '"${value.replaceAll('"', '""')}"';
}

@visibleForTesting
String cmdQuoteForTesting(String value) {
  return _cmdQuote(value);
}

String _shQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

@visibleForTesting
String shQuoteForTesting(String value) {
  return _shQuote(value);
}

bool get _isSupportedNativeDesktopTerminalPlatform {
  return _isSupportedNativeDesktopTerminalPlatformFor(
    defaultTargetPlatform,
    isWeb: kIsWeb,
  );
}

final xterm.TerminalTargetPlatform _xtermTargetPlatform =
    _xtermTargetPlatformFor(defaultTargetPlatform);

@visibleForTesting
xterm.TerminalTargetPlatform defaultXtermTargetPlatformForTesting() {
  return _xtermTargetPlatform;
}

bool _isSupportedNativeDesktopTerminalPlatformFor(
  TargetPlatform platform, {
  required bool isWeb,
}) {
  if (isWeb) {
    return false;
  }
  return switch (platform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };
}

xterm.TerminalTargetPlatform _xtermTargetPlatformFor(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android => xterm.TerminalTargetPlatform.android,
    TargetPlatform.iOS => xterm.TerminalTargetPlatform.ios,
    TargetPlatform.fuchsia => xterm.TerminalTargetPlatform.fuchsia,
    TargetPlatform.linux => xterm.TerminalTargetPlatform.linux,
    TargetPlatform.macOS => xterm.TerminalTargetPlatform.macos,
    TargetPlatform.windows => xterm.TerminalTargetPlatform.windows,
  };
}

String _resolveTerminalFontFamily(String fontFamily) {
  if (fontFamily.trim().toLowerCase() == 'jetbrains mono') {
    return GoogleFonts.jetBrainsMono().fontFamily ?? fontFamily;
  }
  return fontFamily.trim().isEmpty ? 'monospace' : fontFamily.trim();
}

Set<int>? _wordSeparatorsFromSettings(String? value) {
  final separators = value?.trim();
  if (separators == null || separators.isEmpty) {
    return null;
  }
  return separators.runes.toSet();
}

extension on TerminalCursorShape {
  xterm.TerminalCursorType toXtermCursorType() {
    return switch (this) {
      TerminalCursorShape.block => xterm.TerminalCursorType.block,
      TerminalCursorShape.bar => xterm.TerminalCursorType.verticalBar,
      TerminalCursorShape.underline => xterm.TerminalCursorType.underline,
    };
  }
}

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

@visibleForTesting
List<String> terminalFontFallbackForTesting() {
  return _terminalFontFallback;
}

Color? _colorFromHex(String? value) {
  final normalized = normalizeTerminalHexColor(value);
  if (normalized == null) {
    return null;
  }
  return Color(0xFF000000 | int.parse(normalized.substring(1), radix: 16));
}

xterm.TerminalTheme _resolveXtermTheme(TerminalSettings settings) {
  final base = terminalThemeForName(settings.themeName);
  final overrides = settings.colorOverrides;
  final cursor = (_colorFromHex(overrides.cursor) ?? base.cursor).withValues(
    alpha: settings.cursorOpacity,
  );
  return xterm.TerminalTheme(
    cursor: cursor,
    selection: _colorFromHex(overrides.selection) ?? base.selection,
    foreground: _colorFromHex(overrides.foreground) ?? base.foreground,
    background: _colorFromHex(overrides.background) ?? base.background,
    black: base.black,
    red: base.red,
    green: base.green,
    yellow: base.yellow,
    blue: base.blue,
    magenta: base.magenta,
    cyan: base.cyan,
    white: base.white,
    brightBlack: base.brightBlack,
    brightRed: base.brightRed,
    brightGreen: base.brightGreen,
    brightYellow: base.brightYellow,
    brightBlue: base.brightBlue,
    brightMagenta: base.brightMagenta,
    brightCyan: base.brightCyan,
    brightWhite: base.brightWhite,
    searchHitBackground: base.searchHitBackground,
    searchHitBackgroundCurrent: base.searchHitBackgroundCurrent,
    searchHitForeground: base.searchHitForeground,
  );
}

typedef _ReadNative =
    ffi.IntPtr Function(
      ffi.Int32 fd,
      ffi.Pointer<ffi.Uint8> buf,
      ffi.UintPtr nbyte,
    );
typedef _ReadDart = int Function(int fd, ffi.Pointer<ffi.Uint8> buf, int nbyte);

typedef _ErrnoLocationNative = ffi.Pointer<ffi.Int32> Function();
typedef _ErrnoLocationDart = ffi.Pointer<ffi.Int32> Function();

final ffi.DynamicLibrary _libc = ffi.DynamicLibrary.process();
final _ReadDart _posixRead = _libc.lookupFunction<_ReadNative, _ReadDart>(
  'read',
);

int _currentErrno() {
  final symbol = (Platform.isMacOS || Platform.isIOS)
      ? '__error'
      : '__errno_location';
  return _libc
      .lookupFunction<_ErrnoLocationNative, _ErrnoLocationDart>(symbol)()
      .value;
}

@visibleForTesting
int currentErrnoForTesting() {
  return _currentErrno();
}

const int _eintr = 4;
const int _readChunkSize = 4096;

void _posixPtyReadIsolate(List<Object?> args) {
  final fd = args[0]! as int;
  final sendPort = args[1]! as SendPort;
  _runPosixPtyReadIsolate(fd: fd, sendPort: sendPort, read: _posixRead);
}

void _runPosixPtyReadIsolate({
  required int fd,
  required SendPort sendPort,
  required int Function(int, ffi.Pointer<ffi.Uint8>, int) read,
}) {
  if (fd < 0) {
    sendPort.send(const <Object?, Object?>{
      'type': 'error',
      'error': 'PTY master file descriptor is unavailable.',
    });
    return;
  }
  final buffer = calloc<ffi.Uint8>(_readChunkSize);
  try {
    _readPosixPtyLoop(fd: fd, sendPort: sendPort, buffer: buffer, read: read);
  } catch (error) {
    sendPort.send(<Object?, Object?>{
      'type': 'error',
      'error': error.toString(),
    });
  } finally {
    calloc.free(buffer);
  }
}

void _readPosixPtyLoop({
  required int fd,
  required SendPort sendPort,
  required ffi.Pointer<ffi.Uint8> buffer,
  required int Function(int, ffi.Pointer<ffi.Uint8>, int) read,
}) {
  while (true) {
    final byteCount = read(fd, buffer, _readChunkSize);
    if (byteCount > 0) {
      sendPort.send(Uint8List.fromList(buffer.asTypedList(byteCount)));
      continue;
    }
    if (byteCount < 0 && _currentErrno() == _eintr) {
      continue;
    }
    sendPort.send(const <Object?, Object?>{'type': 'done'});
    break;
  }
}

@visibleForTesting
void runPosixPtyReadIsolateForTesting({
  required int fd,
  required SendPort sendPort,
  required int Function(int, ffi.Pointer<ffi.Uint8>, int) read,
}) {
  _runPosixPtyReadIsolate(fd: fd, sendPort: sendPort, read: read);
}

bool _writePtyBytes({
  required List<int> bytes,
  required int Function(Uint8List bytes) write,
  required StreamController<TerminalPtySessionEvent> events,
}) {
  try {
    return write(Uint8List.fromList(bytes)) > 0;
  } catch (error) {
    events.add(TerminalPtyErrorEvent(error));
    return false;
  }
}

void _resizePty({
  required int rows,
  required int cols,
  required void Function({required int rows, required int cols}) resize,
  required StreamController<TerminalPtySessionEvent> events,
}) {
  try {
    resize(rows: rows, cols: cols);
  } catch (error) {
    events.add(TerminalPtyErrorEvent(error));
  }
}

@visibleForTesting
bool writePtyBytesForTesting({
  required List<int> bytes,
  required int Function(Uint8List bytes) write,
  required StreamController<TerminalPtySessionEvent> events,
}) {
  return _writePtyBytes(bytes: bytes, write: write, events: events);
}

@visibleForTesting
void resizePtyForTesting({
  required int rows,
  required int cols,
  required void Function({required int rows, required int cols}) resize,
  required StreamController<TerminalPtySessionEvent> events,
}) {
  _resizePty(rows: rows, cols: cols, resize: resize, events: events);
}

@visibleForTesting
void posixPtyReadIsolateForTesting(List<Object?> args) {
  _posixPtyReadIsolate(args);
}

@visibleForTesting
bool isSupportedNativeDesktopTerminalPlatformForTesting(
  TargetPlatform platform, {
  bool isWeb = false,
}) {
  return _isSupportedNativeDesktopTerminalPlatformFor(platform, isWeb: isWeb);
}

@visibleForTesting
xterm.TerminalTargetPlatform xtermTargetPlatformForTesting(
  TargetPlatform platform,
) {
  return _xtermTargetPlatformFor(platform);
}

@visibleForTesting
String resolveTerminalFontFamilyForTesting(String fontFamily) {
  return _resolveTerminalFontFamily(fontFamily);
}

@visibleForTesting
Set<int>? wordSeparatorsFromSettingsForTesting(String? value) {
  return _wordSeparatorsFromSettings(value);
}

@visibleForTesting
xterm.TerminalCursorType xtermCursorTypeForTesting(TerminalCursorShape shape) {
  return shape.toXtermCursorType();
}

@visibleForTesting
Color? colorFromHexForTesting(String? value) {
  return _colorFromHex(value);
}

@visibleForTesting
xterm.TerminalTheme resolveXtermThemeForTesting(TerminalSettings settings) {
  return _resolveXtermTheme(settings);
}

@visibleForTesting
void feedTerminalInputForTesting(TerminalSessionHandle session, String data) {
  (session as _XtermTerminalSessionHandle)._handleTerminalInput(data);
}

@visibleForTesting
void writeTerminalOutputForTesting(TerminalSessionHandle session, String data) {
  (session as _XtermTerminalSessionHandle)._handleTerminalOutput(data);
}

@visibleForTesting
void setTerminalTitleForTesting(TerminalSessionHandle session, String title) {
  (session as _XtermTerminalSessionHandle)._handleTitleChanged(title);
}

@visibleForTesting
void handleTerminalResizeForTesting(
  TerminalSessionHandle session,
  int width,
  int height,
  int pixelWidth,
  int pixelHeight,
) {
  (session as _XtermTerminalSessionHandle)._handleTerminalResize(
    width,
    height,
    pixelWidth,
    pixelHeight,
  );
}

@visibleForTesting
void flushPendingPtyResizeForTesting(TerminalSessionHandle session) {
  (session as _XtermTerminalSessionHandle)._flushPendingPtyResize();
}

@visibleForTesting
void handlePrivateOscForTesting(
  TerminalSessionHandle session,
  String code,
  List<String> args,
) {
  (session as _XtermTerminalSessionHandle)._handlePrivateOsc(code, args);
}

@visibleForTesting
FocusNode terminalFocusNodeForTesting(TerminalSessionHandle session) {
  return (session as _XtermTerminalSessionHandle)._focusNode;
}

@visibleForTesting
void requestTerminalFocusNowForTesting(TerminalSessionHandle session) {
  (session as _XtermTerminalSessionHandle)._requestFocusNow();
}
