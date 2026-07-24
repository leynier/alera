import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_accessory_layout_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_input_mode_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_input_mode.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_accessory_bar.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_compose_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
            TerminalComposeBar(
              onSend: (text, {required bool withEnter}) {
                notifier.write(utf8.encode(withEnter ? '$text\r' : text));
              },
            ),
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
  late final Terminal _terminal;
  late final TerminalController _controller;
  StreamSubscription<Uint8List>? _outputSub;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 5000,
      onOutput: widget.onInput,
      onResize: (width, height, _, _) => widget.onViewportResize(width, height),
    );
    _controller = TerminalController();
    if (widget.session.snapshot.isNotEmpty) {
      _terminal.write(
        utf8.decode(widget.session.snapshot, allowMalformed: true),
      );
    }
    _outputSub = widget.session.output.listen((data) {
      _terminal.write(utf8.decode(data, allowMalformed: true));
    });
  }

  @override
  void dispose() {
    unawaited(_outputSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direct = widget.inputMode == TerminalInputMode.direct;
    return ColoredBox(
      color: AleraTokens.background,
      child: TerminalView(
        _terminal,
        controller: _controller,
        // Compose mode keeps the terminal read-only so tapping it scrolls
        // instead of raising the soft keyboard; direct mode streams keys.
        readOnly: !direct,
        autofocus: direct,
        backgroundOpacity: 0,
        textStyle: const TerminalStyle(fontFamily: AleraTokens.monoFontFamily),
        padding: const EdgeInsets.all(AleraTokens.spaceSm),
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
