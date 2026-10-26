import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/alera_tokens.dart';
import '../icons/alera_icons.dart';
import '../surfaces/alera_active_rail.dart';

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

/// Messages waiting behind a running turn. With [onReorder], a long press
/// lifts a row to drag it to a new place, and Alt+Up or Alt+Down moves the
/// row that holds a hardware keyboard's focus. The row named by [editingId]
/// is being edited in the composer and offers only [onCancelEdit].
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
    this.onReorder,
    this.editingId,
    this.onCancelEdit,
  });
  final List<AleraQueuedMessageRow> messages;
  final bool canSteer;
  final bool paused;
  final Future<void> Function(String id) onEdit;
  final Future<void> Function(String id) onRemove;
  final Future<void> Function(String id) onSteer;
  final VoidCallback? onTogglePaused;
  final VoidCallback? onReconcile;

  /// Moves a message to a zero-based position in [messages].
  final Future<void> Function(String id, int index)? onReorder;
  final String? editingId;
  final VoidCallback? onCancelEdit;

  @override
  State<AleraMessageQueue> createState() => _AleraMessageQueueState();
}

class _AleraMessageQueueState extends State<AleraMessageQueue> {
  bool _expanded = false;
  final Set<String> _pending = {};

  /// The order shown while a move waits for the runtime's answer.
  List<String>? _movedOrder;
  bool _moving = false;
  String? _dragging;

  @override
  void didUpdateWidget(covariant AleraMessageQueue oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent rebuilds the list often; only a new order from the runtime
    // replaces the one shown while a move is pending.
    final before = [for (final row in oldWidget.messages) row.id];
    final after = [for (final row in widget.messages) row.id];
    if (!listEquals(before, after)) _movedOrder = null;
  }

  Future<void> _run(String id, Future<void> Function(String) action) async {
    if (_pending.contains(id)) return;
    setState(() => _pending.add(id));
    try {
      await action(id);
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  List<AleraQueuedMessageRow> get _ordered {
    final order = _movedOrder;
    if (order == null) return widget.messages;
    final byId = {for (final row in widget.messages) row.id: row};
    final moved = [
      for (final id in order)
        if (byId.remove(id) case final AleraQueuedMessageRow row) row,
    ];
    return [...moved, ...byId.values];
  }

  bool get _canReorder =>
      widget.onReorder != null && widget.messages.length > 1 && !_moving;

  Future<void> _move(String id, int index) async {
    final onReorder = widget.onReorder;
    final rows = _ordered;
    final from = rows.indexWhere((row) => row.id == id);
    if (onReorder == null || _moving || from < 0) return;
    final to = index.clamp(0, rows.length - 1);
    if (from == to) return;
    final order = [for (final row in rows) row.id]..removeAt(from);
    order.insert(to, id);
    setState(() {
      _movedOrder = order;
      _moving = true;
    });
    try {
      await onReorder(id, to);
    } finally {
      if (mounted) {
        setState(() {
          _moving = false;
          _movedOrder = null;
        });
      }
    }
  }

  KeyEventResult _onRowKey(String id, int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!_canReorder ||
        !keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        (!up && event.logicalKey != LogicalKeyboardKey.arrowDown)) {
      return KeyEventResult.ignored;
    }
    final target = up ? index - 1 : index + 1;
    if (target >= 0 && target < widget.messages.length) {
      _move(id, target);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered;
    final rows = _expanded ? ordered : ordered.take(3).toList();
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
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, row) in rows.indexed)
                      _target(context, row, index, ordered, constraints),
                  ],
                ),
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

  /// A row a dragged message can land on: it takes that row's place, and a
  /// line marks the side it lands on.
  Widget _target(
    BuildContext context,
    AleraQueuedMessageRow row,
    int index,
    List<AleraQueuedMessageRow> ordered,
    BoxConstraints constraints,
  ) {
    return DragTarget<String>(
      key: ValueKey('queue-${row.id}'),
      onWillAcceptWithDetails: (details) =>
          _canReorder && details.data != row.id,
      onAcceptWithDetails: (details) => _move(details.data, index),
      builder: (context, candidates, _) {
        final from = candidates.isEmpty
            ? -1
            : ordered.indexWhere((entry) => entry.id == candidates.first);
        final marker = BorderSide(
          color: from < 0 ? Colors.transparent : AleraTokens.accent,
          width: AleraTokens.activeRailWidth,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: from > index ? marker : BorderSide.none,
              bottom: from >= 0 && from < index ? marker : BorderSide.none,
            ),
          ),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, event) => _onRowKey(row.id, index, event),
            child: Opacity(
              opacity: _dragging == row.id ? 0.5 : 1,
              child: _draggable(
                row,
                constraints,
                _row(context, row, index, constraints),
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _canLift => widget.onReorder != null && widget.messages.length > 1;

  Widget _label(AleraQueuedMessageRow row) => Text(
    row.text.isEmpty ? 'Attachment' : row.text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  Widget _grip() => const Padding(
    padding: EdgeInsets.only(right: AleraTokens.space4),
    child: Icon(
      AleraIcons.dragHandle,
      size: AleraTokens.space16,
      color: AleraTokens.foregroundFaint,
    ),
  );

  /// A long press lifts the whole row, so the buttons keep their taps.
  Widget _draggable(
    AleraQueuedMessageRow row,
    BoxConstraints constraints,
    Widget child,
  ) {
    if (!_canLift) return child;
    return Semantics(
      hint: 'Long press and drag to reorder',
      child: LongPressDraggable<String>(
        data: row.id,
        maxSimultaneousDrags: _canReorder ? 1 : 0,
        onDragStarted: () => setState(() => _dragging = row.id),
        onDragEnd: (_) => setState(() => _dragging = null),
        feedback: _DragFeedback(text: row.text, width: constraints.maxWidth),
        child: child,
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AleraQueuedMessageRow row,
    int index,
    BoxConstraints constraints,
  ) {
    final pending = _pending.contains(row.id) || row.status == 'sending';
    final editable =
        !pending && (row.status == 'queued' || row.status == 'failed');
    final editing = row.id == widget.editingId;
    return AleraActiveRail(
      active: editing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_canLift) _grip(),
              Icon(
                row.hasImage ? AleraIcons.viewImage : AleraIcons.queuedMessage,
                size: AleraTokens.space16,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                // A tooltip would take the long press that lifts the row.
                child: _canLift
                    ? _label(row)
                    : Tooltip(message: row.text, child: _label(row)),
              ),
              if (row.attachmentCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: AleraTokens.space4),
                  child: Text(
                    '${row.attachmentCount}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              if (editing)
                TextButton(
                  key: ValueKey('queue-cancel-edit-${row.id}'),
                  onPressed: widget.onCancelEdit,
                  child: const Text('Cancel Edit'),
                )
              else ...[
                Tooltip(
                  message: 'Steer Into the Running Turn',
                  child: TextButton.icon(
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
                ),
                Tooltip(
                  message: 'Edit Queued Message',
                  child: _QueueIconButton(
                    key: ValueKey('queue-edit-${row.id}'),
                    icon: AleraIcons.edit,
                    onPressed: editable
                        ? () => _run(row.id, widget.onEdit)
                        : null,
                  ),
                ),
                Tooltip(
                  message: 'Remove Queued Message',
                  child: _QueueIconButton(
                    icon: AleraIcons.delete,
                    onPressed: editable
                        ? () => _run(row.id, widget.onRemove)
                        : null,
                  ),
                ),
              ],
            ],
          ),
          if (row.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space4),
              child: Text(
                row.error!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueIconButton extends StatelessWidget {
  const _QueueIconButton({super.key, required this.icon, this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    constraints: const BoxConstraints.tightFor(
      width: AleraTokens.space32,
      height: AleraTokens.space32,
    ),
    padding: const EdgeInsets.all(AleraTokens.space6),
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: onPressed,
    icon: Icon(icon, size: AleraTokens.space16),
  );
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.text, required this.width});
  final String text;
  final double width;

  @override
  Widget build(BuildContext context) => Material(
    color: AleraTokens.surfaceElevated,
    borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
    child: Container(
      width: width,
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space6,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Text(
        text.isEmpty ? 'Attachment' : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}
