import 'dart:async';
import 'dart:collection';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Returns a clearer wording for an error message, or null to keep the
/// original. It must not throw; a throw is treated as null.
typedef AleraToastErrorClarifier = Future<String?> Function(String message);

/// [clarifyError] rewrites error toasts that have no action of their own. The
/// original text is shown while the rewrite runs and stays shown when it
/// fails; a rewritten toast offers [copyOriginalLabel] so the exact original
/// error is never lost.
class const AleraToastHost({
  super.key,
  final AleraToastErrorClarifier? clarifyError,
  final String clarifyingCaption = 'Clarifying error…',
  final String clarifiedCaption = 'Clarified message',
  final String copyOriginalLabel = 'Copy Original',
}) extends StatefulWidget {
  @override
  State<AleraToastHost> createState() => _AleraToastHostState();
}

class _AleraToastHostState extends State<AleraToastHost> {
  static const int _maxVisibleToasts = 3;

  final List<_ToastEntry> _visible = <_ToastEntry>[];
  final Queue<AleraToastData> _pending = Queue<AleraToastData>();
  final Map<String, Timer> _dismissTimers = <String, Timer>{};

  StreamSubscription<AleraToastData>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = AleraToast.stream.listen(_enqueue);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    _dismissTimers.clear();
    super.dispose();
  }

  void _enqueue(AleraToastData toast) {
    if (!mounted) {
      return;
    }

    if (_visible.length < _maxVisibleToasts) {
      _showToast(toast);
      return;
    }

    _pending.add(toast);
  }

  void _showToast(AleraToastData toast) {
    final clarify = widget.clarifyError;
    final clarifying =
        clarify != null &&
        toast.tone == AleraToastTone.error &&
        !toast.hasAction;
    final entry = _ToastEntry(
      id: UniqueKey().toString(),
      data: toast,
      caption: clarifying ? widget.clarifyingCaption : null,
    );

    setState(() {
      _visible.add(entry);
    });

    if (clarifying) {
      unawaited(_clarify(entry.id, toast, clarify));
      return;
    }
    _scheduleDismiss(entry.id, toast.duration);
  }

  void _scheduleDismiss(String id, Duration duration) {
    _dismissTimers.remove(id)?.cancel();
    _dismissTimers[id] = Timer(duration, () {
      _startExit(id);
    });
  }

  /// The toast stays up while the rewrite runs, so the dismiss timer only
  /// starts once the final text is on screen.
  Future<void> _clarify(
    String id,
    AleraToastData toast,
    AleraToastErrorClarifier clarify,
  ) async {
    String? clarified;
    try {
      clarified = (await clarify(toast.message))?.trim();
    } on Object {
      clarified = null;
    }
    if (!mounted) {
      return;
    }
    final index = _visible.indexWhere((entry) => entry.id == id);
    if (index < 0) {
      return;
    }
    final current = _visible[index];
    final original = toast.message;
    final rewritten =
        clarified != null && clarified.isNotEmpty && clarified != original;
    setState(() {
      _visible[index] = rewritten
          ? current.copyWith(
              data: AleraToastData(
                message: clarified!,
                tone: toast.tone,
                duration: toast.duration,
                actionLabel: widget.copyOriginalLabel,
                onAction: () =>
                    unawaited(Clipboard.setData(ClipboardData(text: original))),
              ),
              caption: widget.clarifiedCaption,
            )
          : current.copyWith(clearCaption: true);
    });
    _scheduleDismiss(id, toast.duration);
  }

  void _startExit(String id) {
    final index = _visible.indexWhere((entry) => entry.id == id);
    if (index < 0) {
      return;
    }

    final current = _visible[index];
    if (current.exiting) {
      return;
    }

    setState(() {
      _visible[index] = current.copyWith(exiting: true);
    });

    Timer(AleraTokens.durationMid, () {
      _removeToast(id);
    });
  }

  void _removeToast(String id) {
    _dismissTimers.remove(id)?.cancel();

    final hasEntry = _visible.any((entry) => entry.id == id);
    if (hasEntry && mounted) {
      setState(() {
        _visible.removeWhere((entry) => entry.id == id);
      });
    }

    if (_pending.isNotEmpty && mounted) {
      final next = _pending.removeFirst();
      _showToast(next);
    }
  }

  void _runAction(String id) {
    final entry = _visible.where((entry) => entry.id == id).firstOrNull;
    if (entry == null || entry.exiting) {
      return;
    }
    entry.data.onAction?.call();
    _startExit(id);
  }

  @override
  Widget build(BuildContext context) {
    if (_visible.isEmpty) {
      return const SizedBox.shrink();
    }

    // Only a card with an action takes pointer input; the rest of the host,
    // and every plain toast, lets clicks through to the workbench below.
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(
          right: AleraTokens.space16,
          bottom: AleraTokens.space16,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .end,
          children: <Widget>[
            for (final (i, entry) in _visible.indexed) ...<Widget>[
              IgnorePointer(
                ignoring: !entry.data.hasAction,
                child: _ToastCard(
                  entry: entry,
                  onAction: () => _runAction(entry.id),
                ),
              ),
              if (i < _visible.length - 1)
                const SizedBox(height: AleraTokens.space8),
            ],
          ],
        ),
      ),
    );
  }
}

class const _ToastCard({
  required final _ToastEntry entry,
  required final VoidCallback onAction,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final icon = _iconForTone(entry.data.tone);
    final iconColor = _colorForTone(entry.data.tone);
    final textStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: AleraTokens.foreground);
    final captionStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);

    return AnimatedOpacity(
      opacity: entry.exiting ? 0 : 1,
      duration: AleraTokens.durationMid,
      child: AnimatedSlide(
        duration: AleraTokens.durationMid,
        curve: Curves.easeOut,
        offset: entry.exiting ? const Offset(0.08, 0) : Offset.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AleraTokens.surfaceElevated,
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              border: Border.all(color: AleraTokens.border),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: AleraTokens.shadowSoft,
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space8,
              ),
              child: Row(
                mainAxisSize: .min,
                crossAxisAlignment: entry.data.hasAction ? .center : .start,
                children: <Widget>[
                  Icon(icon, size: 16, color: iconColor),
                  const SizedBox(width: AleraTokens.space8),
                  Flexible(
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .start,
                      children: <Widget>[
                        Text(
                          entry.data.message,
                          style: textStyle,
                          softWrap: true,
                        ),
                        if (entry.caption case final caption?) ...<Widget>[
                          const SizedBox(height: AleraTokens.space2),
                          Text(caption, style: captionStyle),
                        ],
                      ],
                    ),
                  ),
                  if (entry.data.hasAction) ...<Widget>[
                    const SizedBox(width: AleraTokens.space8),
                    TextButton(
                      onPressed: entry.exiting ? null : onAction,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AleraTokens.space8,
                        ),
                      ),
                      child: Text(entry.data.actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForTone(AleraToastTone tone) {
    switch (tone) {
      case AleraToastTone.success:
        return AleraIcons.success;
      case AleraToastTone.warning:
        return AleraIcons.warning;
      case AleraToastTone.error:
        return AleraIcons.error;
      case AleraToastTone.info:
        return AleraIcons.info;
    }
  }

  Color _colorForTone(AleraToastTone tone) {
    switch (tone) {
      case AleraToastTone.success:
        return AleraTokens.success;
      case AleraToastTone.warning:
        return AleraTokens.warning;
      case AleraToastTone.error:
        return AleraTokens.error;
      case AleraToastTone.info:
        return AleraTokens.accent;
    }
  }
}

class const _ToastEntry({
  required final String id,
  required final AleraToastData data,
  final bool exiting = false,
  final String? caption,
}) {
  _ToastEntry copyWith({
    bool? exiting,
    AleraToastData? data,
    String? caption,
    bool clearCaption = false,
  }) {
    return _ToastEntry(
      id: id,
      data: data ?? this.data,
      exiting: exiting ?? this.exiting,
      caption: clearCaption ? null : caption ?? this.caption,
    );
  }
}
