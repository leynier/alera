import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:flutter/material.dart';

/// One event of an [AleraTimeline]. Consecutive entries that share a [day]
/// sit under one heading. [open] marks an event that still needs something,
/// such as an unanswered question; [body] is expanded content under the row.
class const AleraTimelineEntry({
  required final String id,
  required final String day,
  required final String time,
  required final String title,
  final String? detail,
  final bool open = false,
  final List<Widget> actions = const <Widget>[],
  final Widget? body,
});

/// Chronological event log grouped by day. Rows are built lazily, so a run
/// with hundreds of events stays cheap, and each row is keyed by its entry id
/// so expanded rows keep their state when entries arrive above them.
class const AleraTimeline({
  super.key,
  required final List<AleraTimelineEntry> entries,
  final Widget? header,
  final Widget? footer,
  final String? emptyMessage,
  final EdgeInsetsGeometry? padding,
}) extends StatelessWidget {
  static const String _keyPrefix = 'timeline:';

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final footer = this.footer;
    final emptyMessage = this.emptyMessage;
    final leading = header == null ? 0 : 1;
    final showEmpty = entries.isEmpty && emptyMessage != null;
    final middle = showEmpty ? 1 : entries.length;
    final indexById = <String, int>{
      for (final (index, entry) in entries.indexed) entry.id: index,
    };
    return ListView.builder(
      padding: padding,
      itemCount: leading + middle + (footer == null ? 0 : 1),
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String> || !key.value.startsWith(_keyPrefix)) {
          return null;
        }
        final index = indexById[key.value.substring(_keyPrefix.length)];
        return index == null ? null : leading + index;
      },
      itemBuilder: (context, index) {
        if (header != null && index == 0) {
          return header;
        }
        final position = index - leading;
        if (position >= middle) {
          return footer;
        }
        if (showEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AleraTokens.space16),
            child: Text(
              emptyMessage,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.foregroundMuted),
            ),
          );
        }
        final entry = entries[position];
        final previous = position > 0 ? entries[position - 1] : null;
        final next = position + 1 < entries.length
            ? entries[position + 1]
            : null;
        final startsDay = previous == null || previous.day != entry.day;
        return _AleraTimelineRow(
          key: ValueKey<String>('$_keyPrefix${entry.id}'),
          entry: entry,
          showDay: startsDay,
          connectAbove: !startsDay,
          connectBelow: next != null && next.day == entry.day,
        );
      },
    );
  }
}

class const _AleraTimelineRow({
  super.key,
  required final AleraTimelineEntry entry,
  required final bool showDay,
  required final bool connectAbove,
  required final bool connectBelow,
}) extends StatelessWidget {
  static const double _rowPadding = AleraTokens.space6;
  static const double _markerTop = _rowPadding + AleraTokens.space4;
  static const double _markerSize = AleraTokens.space8;
  static const double _markerSlot = AleraTokens.space12;
  static const double _connectorLeft =
      AleraTokens.space12 +
      AleraTokens.space48 +
      AleraTokens.space8 +
      (_markerSlot - AleraTokens.dividerExtent) / 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = entry.detail;
    final body = entry.body;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: _rowPadding,
      ),
      child: Row(
        crossAxisAlignment: .start,
        children: <Widget>[
          SizedBox(
            width: AleraTokens.space48,
            child: Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space2),
              child: Text(
                entry.time,
                maxLines: 1,
                softWrap: false,
                overflow: .ellipsis,
                style: AleraTokens.monoCompactStyle,
              ),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          SizedBox(
            width: _markerSlot,
            child: Padding(
              padding: const EdgeInsets.only(top: _markerTop - _rowPadding),
              child: Center(child: _AleraTimelineMarker(open: entry.open)),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Text(
                  entry.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foreground,
                  ),
                ),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: AleraTokens.space2),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
                if (body != null) ...<Widget>[
                  const SizedBox(height: AleraTokens.space8),
                  body,
                ],
              ],
            ),
          ),
          if (entry.actions.isNotEmpty) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            Wrap(
              spacing: AleraTokens.space4,
              runSpacing: AleraTokens.space4,
              crossAxisAlignment: .center,
              children: entry.actions,
            ),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        if (showDay) AleraSectionHeader(label: entry.day),
        Stack(
          children: <Widget>[
            if (connectAbove)
              const Positioned(
                left: _connectorLeft,
                top: 0,
                height: _markerTop,
                child: _AleraTimelineConnector(),
              ),
            if (connectBelow)
              const Positioned(
                left: _connectorLeft,
                top: _markerTop + _markerSize,
                bottom: 0,
                child: _AleraTimelineConnector(),
              ),
            row,
          ],
        ),
      ],
    );
  }
}

class const _AleraTimelineConnector() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: AleraTokens.dividerExtent,
    child: ColoredBox(color: AleraTokens.borderSubtle),
  );
}

/// Filled muted dot for a settled event, warning ring for an open one.
class const _AleraTimelineMarker({required final bool open})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey<String>(open ? 'timelineMarkerOpen' : 'timelineMarker'),
      width: _AleraTimelineRow._markerSize,
      height: _AleraTimelineRow._markerSize,
      decoration: BoxDecoration(
        shape: .circle,
        color: open ? Colors.transparent : AleraTokens.foregroundMuted,
        border: open
            ? Border.all(
                color: AleraTokens.warning,
                width: AleraTokens.strokeThin,
              )
            : null,
      ),
    );
  }
}
