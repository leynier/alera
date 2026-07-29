part of 'agent_quota_status_bar.dart';

class _CodexResetCreditsPanel extends ConsumerStatefulWidget {
  const _CodexResetCreditsPanel({
    required this.hostId,
    required this.snapshot,
    this.compact = false,
  });

  final String hostId;
  final AgentQuotaSnapshot snapshot;
  final bool compact;

  @override
  ConsumerState<_CodexResetCreditsPanel> createState() =>
      _CodexResetCreditsPanelState();
}

class _CodexResetCreditsPanelState
    extends ConsumerState<_CodexResetCreditsPanel> {
  Timer? _expiryTimer;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _scheduleExpiryRefresh();
  }

  @override
  void didUpdateWidget(covariant _CodexResetCreditsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.rateLimitResetCredits?.nextExpiresAt !=
        widget.snapshot.rateLimitResetCredits?.nextExpiresAt) {
      _scheduleExpiryRefresh();
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _scheduleExpiryRefresh() {
    _expiryTimer?.cancel();
    final expiry = widget.snapshot.rateLimitResetCredits?.nextExpiresAt;
    if (expiry == null) return;
    final remaining = expiry.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) return;
    final interval = remaining > const Duration(days: 1)
        ? const Duration(hours: 1)
        : const Duration(minutes: 1);
    _expiryTimer = Timer(interval, () {
      if (!mounted) return;
      setState(() {});
      _scheduleExpiryRefresh();
    });
  }

  Future<void> _consume() async {
    final credits = widget.snapshot.rateLimitResetCredits;
    if (_loading || credits == null || !credits.canConsume) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => const AleraConfirmDialog(
            title: 'Use Codex Reset',
            message:
                'Use One Codex Rate-Limit Reset Credit? Alera Will Re-Check The Active Account And Offer Before Applying It.',
            confirmLabel: 'Use Reset',
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _loading = true);
    try {
      final targets = ref.read(sshTargetsProvider).value ?? const <SshTarget>[];
      final target = widget.hostId == 'local'
          ? null
          : targets.where((item) => item.id == widget.hostId).firstOrNull;
      final result = await ref
          .read(agentQuotaServiceProvider)
          .consumeCodexResetCredit(
            hostId: widget.hostId,
            target: target,
            offerRevision: credits.offerRevision,
          );
      if (!mounted) return;
      final (message, tone) = _codexResetOutcomeMessage(result);
      AleraToast.show(context, message: message, tone: tone);
      ref.invalidate(agentQuotaStateProvider);
    } on Object catch (error) {
      if (!mounted) return;
      AleraToast.show(
        context,
        message: 'Codex Reset Failed: $error',
        tone: AleraToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final credits = widget.snapshot.rateLimitResetCredits;
    if (widget.snapshot.provider != AgentQuotaProviderId.codex ||
        credits == null) {
      return const SizedBox.shrink();
    }
    final expiry = _codexResetExpiryText(credits.nextExpiresAt);
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${credits.availableCount} Rate-Limit ${credits.availableCount == 1 ? 'Reset' : 'Resets'} Available',
          style: AleraTokens.monoStyle.copyWith(
            fontSize: 10,
            color: AleraTokens.foregroundMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (expiry != null)
          Text(
            expiry,
            style: AleraTokens.monoStyle.copyWith(
              fontSize: 9,
              color: AleraTokens.foregroundFaint,
            ),
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(
        top: widget.compact ? AleraTokens.space4 : AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: summary),
          if (credits.availableCount > 0)
            TextButton(
              onPressed: credits.canConsume && !_loading ? _consume : null,
              style: TextButton.styleFrom(
                foregroundColor: AleraTokens.accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space6,
                ),
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(_loading ? 'Applying...' : 'Use Reset'),
            ),
        ],
      ),
    );
  }
}

(String, AleraToastTone) _codexResetOutcomeMessage(
  CodexResetConsumeResult result,
) {
  if (result.status == CodexResetConsumeStatus.rejected) {
    return switch (result.reason) {
      'offerChanged' => (
        'Codex Reset Offer Changed. Review The Updated Credits.',
        AleraToastTone.info,
      ),
      _ => ('No Codex Reset Credit Is Available.', AleraToastTone.info),
    };
  }
  return switch (result.outcome) {
    CodexResetConsumeOutcome.reset => (
      'Codex Rate Limit Reset Applied.',
      AleraToastTone.success,
    ),
    CodexResetConsumeOutcome.nothingToReset => (
      'Codex Has No Active Rate Limit To Reset.',
      AleraToastTone.info,
    ),
    CodexResetConsumeOutcome.noCredit => (
      'No Codex Reset Credit Is Available.',
      AleraToastTone.info,
    ),
    CodexResetConsumeOutcome.alreadyRedeemed => (
      'This Codex Reset Was Already Applied.',
      AleraToastTone.info,
    ),
    null => ('Codex Reset Result Was Unavailable.', AleraToastTone.info),
  };
}

String? _codexResetExpiryText(DateTime? expiry) {
  if (expiry == null) return null;
  final remaining = expiry.difference(DateTime.now().toUtc());
  if (remaining <= Duration.zero) return 'Next Reset Expired';
  if (remaining.inDays > 0) {
    return 'Next Reset Expires In ${remaining.inDays}d ${remaining.inHours % 24}h';
  }
  if (remaining.inHours > 0) {
    return 'Next Reset Expires In ${remaining.inHours}h ${remaining.inMinutes % 60}m';
  }
  return 'Next Reset Expires In ${remaining.inMinutes.clamp(1, 59)}m';
}
