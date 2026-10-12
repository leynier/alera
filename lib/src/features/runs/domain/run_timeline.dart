import 'package:dart_mappable/dart_mappable.dart';

part 'run_timeline.mapper.dart';

/// The Timeline's "Show" filter. Each maps to the `kinds` sent to
/// `runs.timeline`; [all] sends none.
@MappableEnum()
enum RunTimelineFilter {
  all('All', <String>[]),
  dispatches('Dispatches', <String>[
    'taskCreated',
    'attemptPrepared',
    'dispatched',
    'accepted',
    'retried',
    'taskCompleted',
    'taskFailed',
    'taskStalled',
    'taskCancelled',
  ]),
  messages('Messages', <String>['message', 'escalation']),
  gates('Gates', <String>[
    'planProposed',
    'planApproved',
    'planRejected',
    'changesRequested',
    'gateOpened',
    'gateResolved',
  ]),
  integrations('Integrations', <String>[
    'integrationStarted',
    'integrated',
    'conflict',
  ]);

  RunTimelineFilter(this.label, this.kinds);

  final String label;
  final List<String> kinds;
}

/// One `runs.timeline` row: a run event or a message between run agents.
@MappableClass()
class RunTimelineEntry with RunTimelineEntryMappable {
  const RunTimelineEntry({
    required this.id,
    required this.source,
    required this.kind,
    required this.createdAt,
    this.taskId,
    this.dispatchId,
    this.gateId,
    this.actorKind,
    this.actorId,
    this.summary = '',
    this.payload,
    this.messageType,
    this.from,
    this.to,
    this.threadId,
    this.body,
    this.truncated = false,
    this.workspaceId,
    this.sha,
    this.baseSha,
  });

  final String id;

  /// `event` or `message`.
  final String source;

  /// The event kind, or `message`.
  final String kind;
  final String createdAt;
  final String? taskId;
  final String? dispatchId;
  final String? gateId;
  final String? actorKind;
  final String? actorId;
  final String summary;
  final Object? payload;
  final String? messageType;
  final String? from;
  final String? to;
  final String? threadId;
  final String? body;
  final bool truncated;

  /// Completion and integration events: the workspace holding the result
  /// and the commit range `baseSha..sha`.
  final String? workspaceId;
  final String? sha;
  final String? baseSha;

  bool get isMessage => source == 'message';

  /// Messages, and escalation events, which carry the escalation message's
  /// route and body.
  bool get carriesMessage =>
      isMessage || (kind == 'escalation' && (from != null || to != null));

  /// Whether the entry names an exact commit range to diff.
  bool get hasDiff =>
      workspaceId != null && sha != null && baseSha != null && sha != baseSha;

  /// A value of the event payload, when the payload is an object.
  Object? payloadValue(String key) {
    final value = payload;
    return value is Map ? value[key] : null;
  }
}

@MappableClass()
class RunTimelinePage with RunTimelinePageMappable {
  const RunTimelinePage({
    required this.runId,
    this.items = const <RunTimelineEntry>[],
    this.nextCursor,
  });

  static RunTimelinePage fromJson(Map<String, Object?> json) =>
      RunTimelinePageMapper.fromMap(json);

  final String runId;
  final List<RunTimelineEntry> items;
  final String? nextCursor;
}
