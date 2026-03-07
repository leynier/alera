import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:flutter/material.dart';

class ApprovalCard extends StatefulWidget {
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

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  IconData get _icon {
    if (widget.approval.method.contains('fileChange')) {
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
              controller: _scrollController,
              child: SingleChildScrollView(
                key: const ValueKey<String>('approval-description-scroll'),
                controller: _scrollController,
                child: Text(
                  widget.approval.description,
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
                onPressed: widget.onApprove,
                child: const Text('Allow once'),
              ),
              OutlinedButton(
                onPressed: widget.onApproveForSession,
                child: const Text('Allow for session'),
              ),
              FilledButton(
                onPressed: widget.onDecline,
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
