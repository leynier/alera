import 'package:alera_agent_chat/src/agent_chat_item.dart';

/// Presentation-only joins. Wire identities and append offsets stay on the
/// original items in the thread.
final class AgentChatContinuationProjection {
  AgentChatContinuationProjection._(this.items, this._runs);

  factory AgentChatContinuationProjection.build(
    List<AgentChatItem> items, {
    AgentChatContinuationProjection? previous,
  }) {
    final runs = <_ContinuationRun>[];
    final heads = <String, _ContinuationRun>{};
    final latest = <(String, String), _ContinuationRun>{};
    for (final item in items) {
      if (item.wireType == 'payload' && item.normalized['hidden'] == true) {
        continue;
      }
      final segment = _Segment.fromItem(item);
      final key = segment == null ? null : (segment.parentId, segment.stream);
      final existing = segment == null
          ? null
          : latest[key] ?? heads[segment.parentId];
      if (existing != null &&
          segment != null &&
          existing.canAppend(item, segment)) {
        existing.append(item, segment);
        latest[key!] = existing;
        continue;
      }
      if (existing != null &&
          segment != null &&
          existing.compatibleSegment(item, segment)) {
        existing.partial = true;
      }
      final run = _ContinuationRun(item, segment);
      runs.add(run);
      if (key != null) {
        latest[key] = run;
      } else if (!_hasContinuationMetadata(item)) {
        heads[item.id] = run;
      }
    }
    final projected = <AgentChatItem>[];
    final cached = <String, _ContinuationRun>{};
    for (final run in runs) {
      final count = run.first.normalized['segmentCount'];
      if (count is int && count > 0 && run.indexFor('text') + 1 < count) {
        run.partial = true;
      }
      final old = previous?._runs[run.first.id];
      run.item = old != null && run.sameSources(old) ? old.item : run.project();
      projected.add(run.item);
      cached[run.first.id] = run;
    }
    return AgentChatContinuationProjection._(
      List<AgentChatItem>.unmodifiableOf(projected),
      cached,
    );
  }

  final List<AgentChatItem> items;
  final Map<String, _ContinuationRun> _runs;
}

final class _Segment {
  const _Segment(this.parentId, this.index, this.stream);

  static _Segment? fromItem(AgentChatItem item) {
    final parentId = item.normalized['continuationOf'];
    final index = item.normalized['segmentIndex'];
    final stream =
        item.normalized['stream'] ??
        (item.type == AgentChatItemType.userMessage ? 'text' : null);
    if (parentId is! String ||
        parentId.trim().isEmpty ||
        parentId == item.id ||
        index is! int ||
        index <= 0 ||
        (stream != 'text' && stream != 'reasoningText' && stream != 'output')) {
      return null;
    }
    return _Segment(parentId, index, stream as String);
  }

  final String parentId;
  final int index;
  final String stream;
}

final class _ContinuationRun {
  _ContinuationRun(AgentChatItem item, _Segment? segment)
    : sources = <AgentChatItem>[item],
      lastIndexes = <String, int>{
        if (segment != null) segment.stream: segment.index,
      },
      orphanStream = segment?.stream,
      partial = segment != null || _hasContinuationMetadata(item);

  final List<AgentChatItem> sources;
  final Map<String, int> lastIndexes;
  final String? orphanStream;
  bool partial;
  late AgentChatItem item;

  AgentChatItem get first => sources.first;

  int indexFor(String stream) => lastIndexes[stream] ?? 0;

  bool matches(AgentChatItem next) =>
      first.type == next.type &&
      (first.type != AgentChatItemType.unknown ||
          first.wireType == next.wireType) &&
      first.turnId == next.turnId &&
      first.actor == next.actor &&
      _sameOrigin(first, next);

  bool canAppend(AgentChatItem next, _Segment segment) =>
      segment.index == indexFor(segment.stream) + 1 &&
      _fitsCount(segment) &&
      compatibleSegment(next, segment);

  bool _fitsCount(_Segment segment) {
    final count = first.normalized['segmentCount'];
    return segment.stream != 'text' ||
        count is! int ||
        count <= 0 ||
        segment.index < count;
  }

  bool compatibleSegment(AgentChatItem next, _Segment segment) =>
      (orphanStream == null || orphanStream == segment.stream) &&
      matches(next) &&
      _compatibleFields(first, next) &&
      (segment.stream == 'text' || next.text.isEmpty) &&
      (segment.stream == 'reasoningText' || next.reasoningText.isEmpty) &&
      (segment.stream == 'output' || next.output.isEmpty);

  void append(AgentChatItem next, _Segment segment) {
    sources.add(next);
    lastIndexes[segment.stream] = segment.index;
  }

  bool sameSources(_ContinuationRun other) {
    if (partial != other.partial || sources.length != other.sources.length) {
      return false;
    }
    for (var index = 0; index < sources.length; index += 1) {
      if (!identical(sources[index], other.sources[index])) return false;
    }
    return true;
  }

  AgentChatItem project() {
    if (sources.length == 1 && !partial) return first;
    final text = StringBuffer();
    final reasoning = StringBuffer();
    final output = StringBuffer();
    var updatedAt = first.updatedAt;
    var streaming = false;
    var status = AgentChatItemStatus.completed;
    for (final source in sources) {
      text.write(source.text);
      reasoning.write(source.reasoningText);
      output.write(source.output);
      if (source.updatedAt.isAfter(updatedAt)) updatedAt = source.updatedAt;
      streaming = streaming || source.isInProgress;
      if (source.status == AgentChatItemStatus.failed ||
          (status != AgentChatItemStatus.failed &&
              source.status == AgentChatItemStatus.declined)) {
        status = source.status;
      }
    }
    if (status == AgentChatItemStatus.completed && streaming) {
      status = AgentChatItemStatus.inProgress;
    }
    if (status == AgentChatItemStatus.failed ||
        status == AgentChatItemStatus.declined) {
      streaming = false;
    }
    return first.copyWith(
      text: text.toString(),
      reasoningText: reasoning.toString(),
      output: output.toString(),
      updatedAt: updatedAt,
      status: status,
      streaming: streaming,
      isPartialContinuation: partial,
    );
  }
}

bool _hasContinuationMetadata(AgentChatItem item) =>
    item.normalized.containsKey('continuationOf') ||
    item.normalized.containsKey('segmentIndex');

bool _sameOrigin(AgentChatItem first, AgentChatItem next) {
  final a = first.origin;
  final b = next.origin;
  return a?.kind == b?.kind &&
      a?.senderChatId == b?.senderChatId &&
      _sameValue(a?.taskIds, b?.taskIds) &&
      _sameValue(first.normalized['origin'], next.normalized['origin']);
}

bool _compatibleFields(AgentChatItem first, AgentChatItem next) {
  final scalars = <(Object?, Object?)>[
    (first.title, next.title),
    (first.detail, next.detail),
    (first.command, next.command),
    (first.cwd, next.cwd),
    (first.exitCode, next.exitCode),
    (first.durationMs, next.durationMs),
    (first.toolName, next.toolName),
    (first.server, next.server),
    (first.input, next.input),
    (first.result, next.result),
    (first.query, next.query),
    (first.url, next.url),
    (first.imagePath, next.imagePath),
    (first.explanation, next.explanation),
    (first.agentId, next.agentId),
    (first.parentItemId, next.parentItemId),
  ];
  if (next.clientMessageId != null ||
      scalars.any((pair) => pair.$2 != null && !_sameValue(pair.$1, pair.$2))) {
    return false;
  }
  if (next.data.isNotEmpty && !_sameValue(first.data, next.data)) return false;
  if (next.attachments.isNotEmpty &&
      !_sameValue(
        first.attachments.map((value) => value.toJson()).toList(),
        next.attachments.map((value) => value.toJson()).toList(),
      )) {
    return false;
  }
  if (next.changes.isNotEmpty && !_sameValue(_changes(first), _changes(next)))
    return false;
  if (next.planSteps.isNotEmpty && !_sameValue(_steps(first), _steps(next)))
    return false;
  for (final entry in next.normalized.entries) {
    if (_segmentFields.contains(entry.key)) continue;
    if (!_sameValue(first.normalized[entry.key], entry.value)) return false;
  }
  return true;
}

const _segmentFields = <String>{
  'continuationOf',
  'segmentIndex',
  'segmentCount',
  'stream',
};

List<Object?> _changes(AgentChatItem item) => <Object?>[
  for (final change in item.changes)
    <Object?>[change.path, change.kind, change.diff, change.movePath],
];

List<Object?> _steps(AgentChatItem item) => <Object?>[
  for (final step in item.planSteps) <Object?>[step.step, step.status],
];

bool _sameValue(Object? first, Object? next) {
  if (identical(first, next)) return true;
  if (first is List && next is List) {
    if (first.length != next.length) return false;
    for (var index = 0; index < first.length; index += 1) {
      if (!_sameValue(first[index], next[index])) return false;
    }
    return true;
  }
  if (first is Map && next is Map) {
    if (first.length != next.length) return false;
    for (final key in first.keys) {
      if (!next.containsKey(key) || !_sameValue(first[key], next[key])) {
        return false;
      }
    }
    return true;
  }
  return first == next;
}
