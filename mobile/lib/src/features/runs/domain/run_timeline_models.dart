import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';

/// One event of a run, or one message between its terminals.
class const RunTimelineEntry({
  required final String id,
  required final String source,
  required final String kind,
  final DateTime? createdAt,
  final String? taskId,
  final String? gateId,
  final String? actorKind,
  final String? actorId,
  final String summary = '',
  final String? messageType,
  final String? from,
  final String? to,
  final String? body,
  final bool truncated = false,
}) {
  factory fromJson(Map<String, Object?> json) => RunTimelineEntry(
    id: json.requiredString('id'),
    source: json.optionalString('source') ?? 'event',
    kind: json.optionalString('kind') ?? '',
    createdAt: parseRunTimestamp(json.optionalString('createdAt')),
    taskId: json.optionalString('taskId'),
    gateId: json.optionalString('gateId'),
    actorKind: json.optionalString('actorKind'),
    actorId: json.optionalString('actorId'),
    summary: json.optionalString('summary') ?? '',
    messageType: json.optionalString('messageType'),
    from: json.optionalString('from'),
    to: json.optionalString('to'),
    body: json.optionalString('body'),
    truncated: json['truncated'] == true,
  );

  bool get isMessage => source == 'message';

  /// Messages, and escalation events, which carry the escalation message's
  /// route and body.
  bool get carriesMessage =>
      isMessage || (kind == 'escalation' && (from != null || to != null));
}

/// Newest first; [nextCursor] is opaque and sent back as received.
class const RunTimelinePage({
  required final List<RunTimelineEntry> items,
  final String? nextCursor,
}) {
  factory fromJson(Map<String, Object?> json) => RunTimelinePage(
    items: <RunTimelineEntry>[
      for (final item in json.objectList('items'))
        RunTimelineEntry.fromJson(asJsonMap(item)),
    ],
    nextCursor: json.optionalString('nextCursor'),
  );

  /// Appends [next], skipping entries already shown.
  RunTimelinePage merge(RunTimelinePage next) {
    final seen = <String>{for (final entry in items) entry.id};
    return RunTimelinePage(
      items: <RunTimelineEntry>[
        ...items,
        for (final entry in next.items)
          if (seen.add(entry.id)) entry,
      ],
      nextCursor: next.nextCursor,
    );
  }
}
