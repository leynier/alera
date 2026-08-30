part of 'terminal_tab_view.dart';

class const _OutputEndedBanner({
  required final Future<void> Function() onReconnect,
}) extends StatelessWidget {
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

class const _DirectModeBanner() extends StatelessWidget {
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

class const _TerminalRestoreState({
  required final TerminalRestoreProgress progress,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.background),
      child: Center(
        child: Column(
          mainAxisSize: .min,
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

class const _SessionLoading({
  required final _TerminalLoadingOperation operation,
}) extends StatefulWidget {
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
        mainAxisSize: .min,
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

class const _SessionError({
  required final Object error,
  required final Future<void> Function() onReconnect,
  final Future<void> Function()? onRestart,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: .min,
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
              textAlign: .center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Wrap(
              spacing: AleraTokens.spaceSm,
              runSpacing: AleraTokens.spaceSm,
              alignment: .center,
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
