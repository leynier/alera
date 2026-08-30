part of 'agent_quota_status_bar.dart';

class _ClaudeTryWithTuiButton extends ConsumerStatefulWidget {
  const _ClaudeTryWithTuiButton({required this.hostId, required this.snapshot});

  final String hostId;
  final AgentQuotaSnapshot snapshot;

  @override
  ConsumerState<_ClaudeTryWithTuiButton> createState() =>
      _ClaudeTryWithTuiButtonState();
}

class _ClaudeTryWithTuiButtonState
    extends ConsumerState<_ClaudeTryWithTuiButton> {
  var _loading = false;

  Future<void> _run() async {
    if (_loading) {
      return;
    }
    setState(() => _loading = true);
    // The hover card can be disposed while the TUI request is in flight. Keep
    // its longer-lived scope so the cached result still triggers a refresh.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final hostId = widget.hostId;
      final targets = ref.read(sshTargetsProvider).value ?? const <SshTarget>[];
      final target = hostId == 'local'
          ? null
          : targets.where((candidate) => candidate.id == hostId).firstOrNull;
      await ref
          .read(agentQuotaServiceProvider)
          .fetchClaudeTui(
            hostId: hostId,
            target: target,
            accountId: widget.snapshot.accountId,
            displayName: widget.snapshot.displayName,
          );
    } on Object {
      // Status bar refresh / next poll shows the updated error snapshot.
    } finally {
      container.invalidate(agentQuotaStateProvider);
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: _loading ? null : _run,
        style: TextButton.styleFrom(
          foregroundColor: AleraTokens.accent,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          _loading ? 'Trying with TUI...' : 'Try With TUI',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: _loading ? AleraTokens.foregroundFaint : AleraTokens.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
