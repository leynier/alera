import 'dart:async';
import 'dart:collection';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

class AleraToastHost extends StatefulWidget {
  const AleraToastHost({super.key});

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
    final entry = _ToastEntry(id: UniqueKey().toString(), data: toast);

    setState(() {
      _visible.add(entry);
    });

    _dismissTimers[entry.id] = Timer(toast.duration, () {
      _startExit(entry.id);
    });
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

  @override
  Widget build(BuildContext context) {
    if (_visible.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(
            right: AleraTokens.space16,
            bottom: AleraTokens.space16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (var i = 0; i < _visible.length; i++) ...<Widget>[
                _ToastCard(entry: _visible[i]),
                if (i < _visible.length - 1)
                  const SizedBox(height: AleraTokens.space8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.entry});

  final _ToastEntry entry;

  @override
  Widget build(BuildContext context) {
    final icon = _iconForTone(entry.data.tone);
    final iconColor = _colorForTone(entry.data.tone);
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: AleraTokens.foreground);

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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, size: 16, color: iconColor),
                  const SizedBox(width: AleraTokens.space8),
                  Flexible(
                    child: Text(
                      entry.data.message,
                      style: textStyle,
                      softWrap: true,
                    ),
                  ),
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
      case AleraToastTone.error:
        return AleraTokens.error;
      case AleraToastTone.info:
        return AleraTokens.accent;
    }
  }
}

class _ToastEntry {
  const _ToastEntry({
    required this.id,
    required this.data,
    this.exiting = false,
  });

  final String id;
  final AleraToastData data;
  final bool exiting;

  _ToastEntry copyWith({bool? exiting}) {
    return _ToastEntry(id: id, data: data, exiting: exiting ?? this.exiting);
  }
}
