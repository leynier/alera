import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_accessory_layout_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_input_mode_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_input_mode.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_accessory_bar.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_compose_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_output_batcher.dart';
import 'package:xterm/xterm.dart';

/// One terminal tab filling the available space, with the quick-key bar and
/// the compose/direct input modes stacked above the keyboard.
class TerminalTabView extends ConsumerWidget {
  const TerminalTabView({super.key, required this.hostId, required this.tabId});

  final String hostId;
  final String tabId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(terminalSessionControllerProvider(hostId, tabId));
    final inputMode = ref.watch(terminalInputModeControllerProvider(tabId));
    final accessoryKeys =
        ref
            .watch(terminalAccessoryLayoutControllerProvider)
            .value
            ?.visibleKeys() ??
        const <TerminalAccessoryKey>[];
    final notifier = ref.read(
      terminalSessionControllerProvider(hostId, tabId).notifier,
    );
    return switch (session) {
      AsyncData(value: final tabSession) => Column(
        children: <Widget>[
          Expanded(
            child: _TerminalSurface(
              key: ValueKey<String>(tabSession.sessionId),
              session: tabSession,
              inputMode: inputMode,
              onInput: (data) => notifier.write(utf8.encode(data)),
              onViewportResize: notifier.resize,
            ),
          ),
          if (inputMode == TerminalInputMode.direct) const _DirectModeBanner(),
          TerminalAccessoryBar(
            keys: accessoryKeys,
            inputMode: inputMode,
            onKey: notifier.write,
            onToggleMode: ref
                .read(terminalInputModeControllerProvider(tabId).notifier)
                .toggle,
          ),
          if (inputMode == TerminalInputMode.compose)
            TerminalComposeBar(onSend: notifier.sendComposedText),
        ],
      ),
      AsyncError(:final error) => _SessionError(
        error: error,
        onRetry: () {
          ref.invalidate(terminalSessionControllerProvider(hostId, tabId));
        },
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _TerminalSurface extends StatefulWidget {
  const _TerminalSurface({
    super.key,
    required this.session,
    required this.inputMode,
    required this.onInput,
    required this.onViewportResize,
  });

  final TerminalTabSession session;
  final TerminalInputMode inputMode;
  final ValueChanged<String> onInput;
  final void Function(int cols, int rows) onViewportResize;

  @override
  State<_TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends State<_TerminalSurface> {
  late Terminal _terminal;
  final TerminalController _controller = TerminalController();
  TerminalOutputBatcher? _batcher;
  StreamSubscription<MobileTerminalOutputEvent>? _outputSub;
  bool _outputEnded = false;

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
    super.dispose();
  }

  void _bindSession(TerminalTabSession session, {required bool notify}) {
    unawaited(_outputSub?.cancel());
    _outputSub = null;
    _outputEnded = false;
    _replaceEmulator(notify: notify);
    if (session.snapshot.isNotEmpty) {
      _batcher!.addSnapshot(
        utf8.decode(session.snapshot, allowMalformed: true),
      );
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
      onResize: (width, height, _, _) => widget.onViewportResize(width, height),
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

  @override
  Widget build(BuildContext context) {
    final direct = widget.inputMode == TerminalInputMode.direct;
    return Column(
      children: <Widget>[
        if (_outputEnded) const _OutputEndedBanner(),
        Expanded(
          child: ColoredBox(
            color: AleraTokens.background,
            child: TerminalView(
              _terminal,
              controller: _controller,
              // Compose mode keeps the terminal read-only so tapping it scrolls
              // instead of raising the soft keyboard; direct mode streams keys.
              readOnly: !direct,
              autofocus: direct,
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

class _OutputEndedBanner extends StatelessWidget {
  const _OutputEndedBanner();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AleraTokens.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.spaceLg,
          vertical: AleraTokens.spaceXs,
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.link_off, size: AleraTokens.spaceLg),
            const SizedBox(width: AleraTokens.spaceSm),
            Text(
              'Terminal Output Stopped',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectModeBanner extends StatelessWidget {
  const _DirectModeBanner();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AleraTokens.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.spaceLg,
          vertical: AleraTokens.spaceXs,
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.bolt, size: AleraTokens.spaceLg),
            const SizedBox(width: AleraTokens.spaceSm),
            Text(
              'Keys Go Directly To The Terminal',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionError extends StatelessWidget {
  const _SessionError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.terminal,
              size: AleraTokens.emptyIcon,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Text(
              'Terminal Unavailable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
