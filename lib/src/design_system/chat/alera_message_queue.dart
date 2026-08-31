import 'package:flutter/material.dart';
import '../../app/theme/alera_tokens.dart';
import '../icons/alera_icons.dart';

class AleraQueuedMessageRow {
  const AleraQueuedMessageRow({
    required this.id,
    required this.text,
    this.attachmentCount = 0,
    this.hasImage = false,
    this.status = 'queued',
    this.error,
  });
  final String id;
  final String text;
  final int attachmentCount;
  final bool hasImage;
  final String status;
  final String? error;
}

class AleraMessageQueue extends StatefulWidget {
  const AleraMessageQueue({
    super.key,
    required this.messages,
    required this.canSteer,
    required this.onEdit,
    required this.onRemove,
    required this.onSteer,
    this.paused = false,
    this.onTogglePaused,
    this.onReconcile,
  });
  final List<AleraQueuedMessageRow> messages;
  final bool canSteer;
  final bool paused;
  final Future<void> Function(String id) onEdit;
  final Future<void> Function(String id) onRemove;
  final Future<void> Function(String id) onSteer;
  final VoidCallback? onTogglePaused;
  final VoidCallback? onReconcile;

  @override
  State<AleraMessageQueue> createState() => _AleraMessageQueueState();
}

class _AleraMessageQueueState extends State<AleraMessageQueue> {
  bool _expanded = false;
  final Set<String> _pending = {};

  Future<void> _run(String id, Future<void> Function(String) action) async {
    if (_pending.contains(id)) return;
    setState(() => _pending.add(id));
    try {
      await action(id);
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _expanded ? widget.messages : widget.messages.take(3).toList();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.messages.length} Queued${widget.paused ? ' · Paused' : ''}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              if (widget.onTogglePaused != null)
                TextButton(
                  onPressed: widget.onTogglePaused,
                  child: Text(widget.paused ? 'Resume Queue' : 'Pause Queue'),
                ),
              if (widget.messages.length > 3)
                IconButton(
                  tooltip: _expanded ? 'Collapse Queue' : 'Expand Queue',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? AleraIcons.chevronUp : AleraIcons.chevronDown,
                  ),
                ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: AleraTokens.space48 * 4,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final row in rows) _row(context, row)],
              ),
            ),
          ),
          if (widget.messages.any((message) => message.status == 'uncertain'))
            TextButton(
              onPressed: widget.onReconcile,
              child: const Text('Check Delivery'),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AleraQueuedMessageRow row) {
    final pending = _pending.contains(row.id) || row.status == 'sending';
    final editable =
        !pending && (row.status == 'queued' || row.status == 'failed');
    return Column(
      key: ValueKey('queue-${row.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              row.hasImage ? AleraIcons.viewImage : AleraIcons.queuedMessage,
              size: AleraTokens.space16,
              color: AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Tooltip(
                message: row.text,
                child: Text(
                  row.text.isEmpty ? 'Attachment' : row.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (row.attachmentCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: AleraTokens.space4),
                child: Text(
                  '${row.attachmentCount}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  AleraTokens.space48 * 2,
                  AleraTokens.space32,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space8,
                ),
                foregroundColor: AleraTokens.foregroundMuted,
                textStyle: Theme.of(context).textTheme.labelSmall,
              ),
              onPressed: editable && widget.canSteer
                  ? () => _run(row.id, widget.onSteer)
                  : null,
              icon: Icon(AleraIcons.steer, size: AleraTokens.space12),
              label: Text(pending ? 'Sending' : 'Steer'),
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(
                width: AleraTokens.space32,
                height: AleraTokens.space32,
              ),
              padding: const EdgeInsets.all(AleraTokens.space6),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: 'Remove Queued Message',
              onPressed: editable ? () => _run(row.id, widget.onRemove) : null,
              icon: const Icon(AleraIcons.delete, size: AleraTokens.space16),
            ),
            PopupMenuButton<String>(
              padding: const EdgeInsets.all(AleraTokens.space6),
              style: IconButton.styleFrom(
                minimumSize: const Size.square(AleraTokens.space32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: 'Message Actions',
              enabled: editable,
              onSelected: (_) => _run(row.id, widget.onEdit),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit Message')),
              ],
              icon: const Icon(AleraIcons.more, size: AleraTokens.space16),
            ),
          ],
        ),
        if (row.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space4),
            child: Text(
              row.error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AleraTokens.error),
            ),
          ),
      ],
    );
  }
}
