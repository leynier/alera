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
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
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
          Text(
            approval.description,
            style: const TextStyle(fontSize: 13, color: AleraTokens.foreground),
          ),
          const SizedBox(height: AleraTokens.space8),
          Wrap(
            spacing: AleraTokens.space6,
            children: <Widget>[
              _ApprovalButton(
                label: 'Allow once',
                primary: true,
                onTap: onApprove,
              ),
              _ApprovalButton(
                label: 'Allow for session',
                primary: false,
                onTap: onApproveForSession,
              ),
              _ApprovalButton(
                label: 'Decline',
                primary: false,
                danger: true,
                onTap: onDecline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApprovalButton extends StatelessWidget {
  const _ApprovalButton({
    required this.label,
    required this.primary,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final bool primary;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = primary
        ? AleraTokens.accent
        : danger
            ? Colors.transparent
            : AleraTokens.surface;
    final fg = primary
        ? AleraTokens.onAccent
        : danger
            ? Colors.redAccent
            : AleraTokens.foregroundMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space4,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          border: primary
              ? null
              : Border.all(
                  color: danger
                      ? Colors.redAccent.withValues(alpha: 0.5)
                      : AleraTokens.border,
                ),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
