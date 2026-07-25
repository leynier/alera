import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/keyboard/application/keybinding_resolver.dart';
import 'package:alera/src/features/keyboard/application/keyboard_command_dispatcher.dart';
import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TerminalSurface extends ConsumerStatefulWidget {
  const TerminalSurface({
    super.key,
    required this.session,
    this.autofocus = false,
  });

  final TerminalSessionHandle session;
  final bool autofocus;

  @override
  ConsumerState<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends ConsumerState<TerminalSurface> {
  TerminalVisibilityLease? _visibilityLease;

  @override
  void initState() {
    super.initState();
    _visibilityLease = widget.session.acquireVisibility();
    _scheduleStart(widget.session);
  }

  @override
  void didUpdateWidget(TerminalSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _visibilityLease?.dispose();
      _visibilityLease = widget.session.acquireVisibility();
      _scheduleStart(widget.session);
    }
  }

  @override
  void dispose() {
    _visibilityLease?.dispose();
    _visibilityLease = null;
    super.dispose();
  }

  void _scheduleStart(TerminalSessionHandle session) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.session != session) {
        return;
      }
      unawaited(session.ensureStarted());
    });
  }

  /// Intercepts Alera shortcuts before the key reaches the PTY. Returning
  /// `handled` swallows the key; `ignored` lets the terminal/shell receive it.
  KeyEventResult _handleTerminalKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = ref.read(settingsControllerProvider).keyboard;
    final resolver = KeybindingResolver(settings: keyboard);
    final modifiers = KeyModifierState.fromKeyboard(HardwareKeyboard.instance);
    final resolved = resolver.resolveAction(event, modifiers);
    if (resolved == null) {
      return KeyEventResult.ignored;
    }
    // Under terminal-first, defer everything except bindings explicitly marked
    // as safe to intercept while a terminal is focused.
    if (keyboard.terminalPolicy == TerminalShortcutPolicy.terminalFirst &&
        !resolved.allowInTerminal) {
      return KeyEventResult.ignored;
    }
    KeyboardCommandDispatcher(ref: ref, context: context).dispatch(resolved.id);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        if (widget.session.errorMessage case final String error
            when error.trim().isNotEmpty) {
          return _TerminalErrorState(
            message: error,
            onRetry: widget.session.restart,
          );
        }
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(color: AleraTokens.bg),
                child: widget.session.buildView(
                  autofocus: widget.autofocus,
                  onKeyEvent: _handleTerminalKey,
                ),
              ),
            ),
            if (widget.session.isStarting)
              const Positioned(
                right: AleraTokens.space12,
                top: AleraTokens.space12,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ),
            // Restoring an evicted terminal replays its whole scrollback over
            // several frames. The corner spinner does not read as a wait that
            // long, so cover the area until the history is back.
            Positioned.fill(
              child: ValueListenableBuilder<TerminalRestoreProgress?>(
                valueListenable: widget.session.restoreProgress,
                builder: (context, progress, _) {
                  if (progress == null) {
                    return const SizedBox.shrink();
                  }
                  return _TerminalRestoreState(progress: progress);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TerminalRestoreState extends StatelessWidget {
  const _TerminalRestoreState({required this.progress});

  final TerminalRestoreProgress progress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.bg),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Restoring Terminal',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AleraTokens.space12),
            SizedBox(
              width: 180,
              child: LinearProgressIndicator(value: progress.fraction),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalErrorState extends StatelessWidget {
  const _TerminalErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.all(AleraTokens.space20),
          decoration: BoxDecoration(
            color: AleraTokens.surface,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            border: Border.all(color: AleraTokens.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Terminal Unavailable', style: theme.textTheme.titleMedium),
              const SizedBox(height: AleraTokens.space8),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              const SizedBox(height: AleraTokens.space16),
              FilledButton(
                onPressed: () => unawaited(onRetry()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
