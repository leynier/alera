part of 'codex_chat_surface.dart';

class const _CodexMessageActions({
  required final bool visible,
  required final bool raw,
  required final String copyText,
  required final MainAxisAlignment alignment,
  required final DateTime timestamp,
  required final VoidCallback onToggleRaw,
  final bool timestampFirst = false,
  final CodexTimelineCell? cell,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final buttons = Row(
      mainAxisSize: .min,
      children: <Widget>[
        if (cell != null) _CodexHistoryMessageActions(cell: cell!),
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
          crossAxisAlignment: .center,
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space4,
          children: timestampFirst
              ? <Widget>[?timestampWidget, buttons]
              : <Widget>[buttons, ?timestampWidget],
        ),
      ),
    );
  }
}

class const _CodexMessageTimestamp({required final DateTime timestamp})
    extends StatelessWidget {
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
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(.fromDateTime(local), alwaysUse24HourFormat: false);
    return Text(
      '${weekdays[local.weekday - 1]} $time',
      key: const ValueKey<String>('codex-message-timestamp'),
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AleraTokens.foregroundFaint),
    );
  }
}
