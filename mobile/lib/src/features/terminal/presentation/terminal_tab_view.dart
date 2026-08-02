import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_accessory_layout_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_input_mode_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_input_mode.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_accessory_bar.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_compose_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_output_batcher.dart';
import 'package:logging/logging.dart';
import 'package:xterm/xterm.dart';

part 'terminal_tab_state_widgets.dart';

/// One terminal tab filling the available space, with the quick-key bar and
/// the compose/direct input modes stacked above the keyboard.
class TerminalTabView extends ConsumerStatefulWidget {
  const TerminalTabView({super.key, required this.hostId, required this.tabId});

  final String hostId;
  final String tabId;

  @override
  ConsumerState<TerminalTabView> createState() => _TerminalTabViewState();
}

class _TerminalTabViewState extends ConsumerState<TerminalTabView> {
  final GlobalKey<_TerminalSurfaceState> _surfaceKey =
      GlobalKey<_TerminalSurfaceState>();
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(
      terminalSessionControllerProvider(widget.hostId, widget.tabId),
    );
    final inputMode = ref.watch(
      terminalInputModeControllerProvider(widget.tabId),
    );
    final accessoryKeys =
        ref
            .watch(terminalAccessoryLayoutControllerProvider)
            .value
            ?.visibleKeys() ??
        const <TerminalAccessoryKey>[];
    final notifier = ref.read(
      terminalSessionControllerProvider(widget.hostId, widget.tabId).notifier,
    );
    final content = switch (session) {
      AsyncData(value: final tabSession) => Column(
        children: <Widget>[
          Expanded(
            child: _TerminalSurface(
              key: _surfaceKey,
              session: tabSession,
              inputMode: inputMode,
              onInput: (data) => notifier.write(utf8.encode(data)),
              onViewportResize: notifier.resize,
              onReconnect: notifier.reconnect,
            ),
          ),
          if (inputMode == TerminalInputMode.direct) const _DirectModeBanner(),
          TerminalAccessoryBar(
            keys: accessoryKeys,
            inputMode: inputMode,
            onKey: notifier.write,
            onPaste: () => _pasteClipboard(notifier),
            onToggleMode: ref
                .read(
                  terminalInputModeControllerProvider(widget.tabId).notifier,
                )
                .toggle,
          ),
          if (inputMode == TerminalInputMode.compose)
            TerminalComposeBar(onSend: notifier.sendComposedText),
        ],
      ),
      AsyncError(:final error) => _SessionError(
        error: error,
        onReconnect: notifier.reconnect,
        onRestart: notifier.supportsRestart
            ? () => _confirmRestart(context, notifier)
            : null,
      ),
      AsyncLoading(:final progress) => _SessionLoading(
        operation: switch (progress) {
          0.25 => _TerminalLoadingOperation.reconnecting,
          0.75 => _TerminalLoadingOperation.restarting,
          _ => _TerminalLoadingOperation.starting,
        },
      ),
    };
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        content,
        Positioned(
          top: AleraTokens.spaceXs,
          right: AleraTokens.spaceXs,
          child: AleraIconButton(
            tooltip: _refreshing ? 'Refreshing Terminal' : 'Refresh Terminal',
            icon: _refreshing ? AleraIcons.loading : AleraIcons.refresh,
            backgroundColor: AleraTokens.surfaceElevated,
            borderColor: AleraTokens.borderSubtle,
            onPressed: _refreshing ? null : _refreshTerminal,
          ),
        ),
      ],
    );
  }

  Future<void> _pasteClipboard(TerminalSessionController notifier) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Clipboard has no text')),
          );
        }
        return;
      }
      await notifier.pasteText(text);
    } catch (error, stackTrace) {
      Logger(
        'TerminalTabView',
      ).warning('terminal clipboard paste failed', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not paste clipboard')),
        );
      }
    }
  }

  Future<void> _refreshTerminal() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await _surfaceKey.currentState?.refreshRendering();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _confirmRestart(
    BuildContext context,
    TerminalSessionController notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Restart Terminal?'),
          content: const Text(
            'This will stop the current process tree and start a new shell. Terminal history will be preserved.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restart Terminal'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await notifier.restartTerminal();
    }
  }
}

class _TerminalSurface extends StatefulWidget {
  const _TerminalSurface({
    super.key,
    required this.session,
    required this.inputMode,
    required this.onInput,
    required this.onViewportResize,
    required this.onReconnect,
  });

  final TerminalTabSession session;
  final TerminalInputMode inputMode;
  final ValueChanged<String> onInput;
  final void Function(int cols, int rows) onViewportResize;
  final Future<void> Function() onReconnect;

  @override
  State<_TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends State<_TerminalSurface> {
  late Terminal _terminal;
  final TerminalController _controller = TerminalController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'MobileTerminal');
  TerminalOutputBatcher? _batcher;
  StreamSubscription<MobileTerminalOutputEvent>? _outputSub;
  bool _outputEnded = false;
  int _viewGeneration = 0;
  (int, int)? _suppressedViewportSize;

  @override
  void initState() {
    super.initState();
    _bindSession(widget.session, notify: false);
  }

  @override
  void didUpdateWidget(_TerminalSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The session id is stable across re-attaches, so this State survives a
    // reconnect that hands down a new session over a new client. Without
    // rebinding, the subscription stays on the previous client's closed stream
    // and the terminal freezes on whatever it had drawn.
    if (!identical(oldWidget.session, widget.session)) {
      _bindSession(widget.session, notify: true);
    }
  }

  @override
  void dispose() {
    unawaited(_outputSub?.cancel());
    _batcher?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _bindSession(TerminalTabSession session, {required bool notify}) {
    unawaited(_outputSub?.cancel());
    _outputSub = null;
    _outputEnded = false;
    _replaceEmulator(notify: notify);
    final snapshot = session.takeSnapshot();
    if (snapshot.isNotEmpty) {
      _batcher!.addSnapshot(utf8.decode(snapshot, allowMalformed: true));
    }
    _outputSub = session.output.listen(
      _handleOutput,
      // A closed or errored source is otherwise indistinguishable from a
      // terminal that simply has nothing to say.
      onError: (Object _, StackTrace _) => _markOutputEnded(),
      onDone: _markOutputEnded,
    );
  }

  /// Builds a fresh emulator rather than writing clear sequences into the old
  /// one, so alt-buffer, mouse reporting, and cursor modes reset too.
  void _replaceEmulator({required bool notify}) {
    _batcher?.dispose();
    final next = Terminal(
      maxLines: 5000,
      onOutput: (data) => widget.onInput(data),
      onResize: (width, height, _, _) => _handleViewportResize(width, height),
    );
    // One write per frame. Writing every chunk straight through made a noisy
    // build parse and repaint many times inside a single frame.
    _batcher = TerminalOutputBatcher(write: next.write);
    if (notify) {
      setState(() => _terminal = next);
    } else {
      _terminal = next;
    }
  }

  void _handleOutput(MobileTerminalOutputEvent event) {
    final text = utf8.decode(event.data, allowMalformed: true);
    if (event.replacesScrollback) {
      _replaceEmulator(notify: true);
      _batcher!.addSnapshot(text);
      return;
    }
    _batcher!.add(text);
  }

  void _markOutputEnded() {
    if (!mounted || _outputEnded) {
      return;
    }
    setState(() => _outputEnded = true);
  }

  void _handleViewportResize(int width, int height) {
    final suppressed = _suppressedViewportSize;
    _suppressedViewportSize = null;
    if (suppressed == (width, height)) {
      return;
    }
    widget.onViewportResize(width, height);
  }

  Future<void> refreshRendering() async {
    if (!mounted) {
      return;
    }
    final restoreFocus = _focusNode.hasFocus;
    _suppressedViewportSize = (_terminal.viewWidth, _terminal.viewHeight);
    setState(() => _viewGeneration += 1);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && restoreFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final direct = widget.inputMode == TerminalInputMode.direct;
    return Column(
      children: <Widget>[
        if (_outputEnded) _OutputEndedBanner(onReconnect: widget.onReconnect),
        Expanded(
          child: ColoredBox(
            color: AleraTokens.background,
            child: TerminalView(
              _terminal,
              key: ValueKey<int>(_viewGeneration),
              controller: _controller,
              scrollController: _scrollController,
              focusNode: _focusNode,
              // Compose mode keeps the terminal read-only so tapping it scrolls
              // instead of raising the soft keyboard; direct mode streams keys.
              readOnly: !direct,
              autofocus: direct && _viewGeneration == 0,
              backgroundOpacity: 0,
              textStyle: const TerminalStyle(
                fontFamily: AleraTokens.monoFontFamily,
              ),
              padding: const EdgeInsets.all(AleraTokens.spaceSm),
            ),
          ),
        ),
      ],
    );
  }
}
