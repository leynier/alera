import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:flutter/material.dart';

class ApprovalCard extends StatelessWidget {
  const ApprovalCard({
    super.key,
    required this.approval,
    required this.onApprove,
    required this.onApproveForSession,
    required this.onDecline,
  });

  final PendingApproval approval;
  final VoidCallback onApprove;
  final VoidCallback onApproveForSession;
  final VoidCallback onDecline;

  IconData get _icon {
    if (approval.method.contains('fileChange')) {
      return Icons.edit_document;
    }
    return Icons.terminal;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border.all(color: AleraTokens.border),
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_icon, size: 14, color: AleraTokens.foregroundMuted),
              const SizedBox(width: AleraTokens.space6),
              const Text(
                'Approval required',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const ValueKey<String>('approval-description-scroll'),
                child: Text(
                  approval.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AleraTokens.foreground,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AleraTokens.space8),
          Wrap(
            spacing: AleraTokens.space6,
            children: <Widget>[
              FilledButton(
                onPressed: onApprove,
                child: const Text('Allow once'),
              ),
              OutlinedButton(
                onPressed: onApproveForSession,
                child: const Text('Allow for session'),
              ),
              FilledButton(
                onPressed: onDecline,
                style: FilledButton.styleFrom(
                  backgroundColor: AleraTokens.error,
                  foregroundColor: AleraTokens.onError,
                ),
                child: const Text('Decline'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
