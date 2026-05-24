import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';

class TerminalSurface extends StatefulWidget {
  const TerminalSurface({
    super.key,
    required this.session,
    this.autofocus = false,
  });

  final TerminalSessionHandle session;
  final bool autofocus;

  @override
  State<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends State<TerminalSurface> {
  @override
  void initState() {
    super.initState();
    _scheduleStart(widget.session);
  }

  @override
  void didUpdateWidget(TerminalSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _scheduleStart(widget.session);
    }
  }

  void _scheduleStart(TerminalSessionHandle session) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.session != session) {
        return;
      }
      unawaited(session.ensureStarted());
    });
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
                child: widget.session.buildView(autofocus: widget.autofocus),
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
          ],
        );
      },
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
              Text(
                'Terminal failed to start',
                style: theme.textTheme.titleMedium,
              ),
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
