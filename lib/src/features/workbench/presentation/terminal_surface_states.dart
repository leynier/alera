part of 'terminal_surface.dart';

class const _TerminalOperationState({
  required final TerminalSessionOperation operation,
}) extends StatefulWidget {
  @override
  State<_TerminalOperationState> createState() =>
      _TerminalOperationStateState();
}

class _TerminalOperationStateState extends State<_TerminalOperationState> {
  Timer? _timer;
  late DateTime _startedAt;

  @override
  void initState() {
    super.initState();
    _startClock();
  }

  @override
  void didUpdateWidget(_TerminalOperationState oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.operation != widget.operation) {
      _startClock();
    }
  }

  void _startClock() {
    _timer?.cancel();
    _startedAt = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(_startedAt).inSeconds;
    final label = switch (widget.operation) {
      TerminalSessionOperation.starting => 'Starting terminal',
      TerminalSessionOperation.reconnecting => 'Reconnecting terminal',
      TerminalSessionOperation.restarting => 'Restarting terminal',
    };
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.bg),
      child: Center(
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: AleraTokens.space12),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            if (elapsed >= 3) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                'Elapsed: ${elapsed}s',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.foregroundMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class const _TerminalRestoreState({
  required final TerminalRestoreProgress progress,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.bg),
      child: Center(
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            Text(
              'Restoring terminal',
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

class const _TerminalErrorState({
  required final String message,
  required final Future<void> Function() onReconnect,
  final Future<void> Function()? onRestart,
}) extends StatelessWidget {
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
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: <Widget>[
              Text('Terminal unavailable', style: theme.textTheme.titleMedium),
              const SizedBox(height: AleraTokens.space8),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              const SizedBox(height: AleraTokens.space16),
              Wrap(
                spacing: AleraTokens.space8,
                runSpacing: AleraTokens.space8,
                children: <Widget>[
                  FilledButton(
                    onPressed: () => unawaited(onReconnect()),
                    child: const Text('Reconnect'),
                  ),
                  if (onRestart case final restart?)
                    OutlinedButton(
                      onPressed: () => unawaited(restart()),
                      child: const Text('Restart Terminal'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
