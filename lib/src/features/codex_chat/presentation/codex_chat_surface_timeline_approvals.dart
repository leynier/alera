part of 'codex_chat_surface.dart';

class _CodexApprovalCard extends StatelessWidget {
  const _CodexApprovalCard({required this.request, required this.onApproval});

  final CodexPendingRequest request;
  final Future<void> Function(
    CodexPendingRequest request, {
    required Object decision,
  })
  onApproval;

  @override
  Widget build(BuildContext context) => _CodexRequestCard(
    title: 'Approval Required',
    bodyWidget: ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: AleraTokens.codexRequestMaxHeight,
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          request.approvalDescription,
          style: AleraTokens.monoStyle,
        ),
      ),
    ),
    actions: <Widget>[
      if (request.supportsApprovalDecision('accept'))
        FilledButton(
          onPressed: () => _respond('accept'),
          child: const Text('Allow Once'),
        ),
      if (request.supportsApprovalDecision('acceptForSession'))
        TextButton(
          onPressed: () => _respond('acceptForSession'),
          child: const Text('Allow For Session'),
        ),
      if (request.supportsApprovalDecision('acceptWithExecpolicyAmendment'))
        TextButton(
          onPressed: () => _respond('acceptWithExecpolicyAmendment'),
          child: const Text('Allow Matching Commands'),
        ),
      if (request.supportsApprovalDecision('applyNetworkPolicyAmendment'))
        TextButton(
          onPressed: () => _respond('applyNetworkPolicyAmendment'),
          child: const Text('Apply Network Rule'),
        ),
      if (request.supportsApprovalDecision('decline'))
        TextButton(
          onPressed: () => _respond('decline'),
          child: const Text('Decline'),
        ),
      if (request.supportsApprovalDecision('cancel'))
        TextButton(
          onPressed: () => _respond('cancel'),
          child: const Text('Cancel Turn'),
        ),
    ],
  );

  void _respond(String decision) => unawaited(
    onApproval(request, decision: request.approvalDecisionValue(decision)),
  );
}
