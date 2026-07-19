import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

/// One terminal tab filling the available space. Owns the xterm state and
/// forwards keystrokes and viewport changes to the session controller.
class TerminalTabView extends ConsumerWidget {
  const TerminalTabView({super.key, required this.hostId, required this.tabId});

  final String hostId;
  final String tabId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(terminalSessionControllerProvider(hostId, tabId));
    return switch (session) {
      AsyncData(value: final tabSession) => _TerminalSurface(
        key: ValueKey<String>(tabSession.sessionId),
        session: tabSession,
        onInput: (data) => ref
            .read(terminalSessionControllerProvider(hostId, tabId).notifier)
            .write(utf8.encode(data)),
        onViewportResize: (cols, rows) => ref
            .read(terminalSessionControllerProvider(hostId, tabId).notifier)
            .resize(cols, rows),
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
    required this.onInput,
    required this.onViewportResize,
  });

  final TerminalTabSession session;
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
    return ColoredBox(
      color: AleraTokens.background,
      child: TerminalView(
        _terminal,
        controller: _controller,
        autofocus: true,
        backgroundOpacity: 0,
        textStyle: const TerminalStyle(fontFamily: AleraTokens.monoFontFamily),
        padding: const EdgeInsets.all(AleraTokens.spaceSm),
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
