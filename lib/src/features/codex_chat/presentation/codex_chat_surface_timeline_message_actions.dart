part of 'codex_chat_surface.dart';

class _CodexMessageActions extends StatelessWidget {
  const _CodexMessageActions({
    required this.visible,
    required this.raw,
    required this.copyText,
    required this.alignment,
    required this.timestamp,
    required this.onToggleRaw,
    this.timestampFirst = false,
  });

  final bool visible;
  final bool raw;
  final String copyText;
  final MainAxisAlignment alignment;
  final DateTime timestamp;
  final bool timestampFirst;
  final VoidCallback onToggleRaw;

  @override
  Widget build(BuildContext context) {
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AleraIconButton(
          tooltip: 'Copy Message',
          icon: AleraIcons.copy,
          onPressed: copyText.isEmpty
              ? null
              : () => _copyCodexText(context, copyText, 'Message copied'),
        ),
        const SizedBox(width: AleraTokens.space4),
        AleraIconButton(
          tooltip: raw ? 'Show Markdown' : 'Show Raw Markdown',
          icon: raw ? AleraIcons.text : AleraIcons.code,
          onPressed: onToggleRaw,
        ),
      ],
    );
    final timestampWidget = timestamp.millisecondsSinceEpoch == 0
        ? null
        : _CodexMessageTimestamp(timestamp: timestamp);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: AleraTokens.durationFast,
      child: IgnorePointer(
        ignoring: !visible,
        child: Wrap(
          alignment: alignment == MainAxisAlignment.end
              ? WrapAlignment.end
              : WrapAlignment.start,
          spacing: AleraTokens.space12,
          runSpacing: AleraTokens.space4,
          children: timestampFirst
              ? <Widget>[?timestampWidget, buttons]
              : <Widget>[buttons, ?timestampWidget],
        ),
      ),
    );
  }
}

class _CodexMessageTimestamp extends StatelessWidget {
  const _CodexMessageTimestamp({required this.timestamp});

  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final local = timestamp.toLocal();
    const weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: false,
    );
    return Text(
      '${weekdays[local.weekday - 1]} $time',
      key: const ValueKey<String>('codex-message-timestamp'),
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: AleraTokens.foregroundFaint),
    );
  }
}
