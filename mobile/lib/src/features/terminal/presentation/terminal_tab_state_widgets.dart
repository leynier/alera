part of 'terminal_tab_view.dart';

class _OutputEndedBanner extends StatelessWidget {
  const _OutputEndedBanner({required this.onReconnect});

  final Future<void> Function() onReconnect;

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
              'Terminal output stopped',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const Spacer(),
            TextButton(
              onPressed: () => unawaited(onReconnect()),
              child: const Text('Reconnect'),
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
              'Keys go directly to the terminal',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalRestoreState extends StatelessWidget {
  const _TerminalRestoreState({required this.progress});

  final TerminalRestoreProgress progress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.background),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Restoring terminal',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            SizedBox(
              width: AleraTokens.terminalRestoreProgressWidth,
              child: LinearProgressIndicator(value: progress.fraction),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TerminalLoadingOperation { starting, reconnecting, restarting }

class _SessionLoading extends StatefulWidget {
  const _SessionLoading({required this.operation});

  final _TerminalLoadingOperation operation;

  @override
  State<_SessionLoading> createState() => _SessionLoadingState();
}

class _SessionLoadingState extends State<_SessionLoading> {
  Timer? _timer;
  late DateTime _startedAt;

  @override
  void initState() {
    super.initState();
    _startClock();
  }

  @override
  void didUpdateWidget(_SessionLoading oldWidget) {
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
      _TerminalLoadingOperation.starting => 'Starting terminal',
      _TerminalLoadingOperation.reconnecting => 'Reconnecting terminal',
      _TerminalLoadingOperation.restarting => 'Restarting terminal',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: AleraTokens.spaceMd),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          if (elapsed >= 3) ...<Widget>[
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              'Elapsed: ${elapsed}s',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.foregroundMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionError extends StatelessWidget {
  const _SessionError({
    required this.error,
    required this.onReconnect,
    this.onRestart,
  });

  final Object error;
  final Future<void> Function() onReconnect;
  final Future<void> Function()? onRestart;

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
              'Terminal unavailable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Wrap(
              spacing: AleraTokens.spaceSm,
              runSpacing: AleraTokens.spaceSm,
              alignment: WrapAlignment.center,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: () => unawaited(onReconnect()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reconnect'),
                ),
                if (onRestart case final restart?)
                  OutlinedButton.icon(
                    onPressed: () => unawaited(restart()),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Restart Terminal'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
