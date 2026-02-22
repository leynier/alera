class MarkdownStreamCollectorState {
  const MarkdownStreamCollectorState({this.pendingBuffer = ''});

  final String pendingBuffer;

  MarkdownStreamCollectorState copyWith({String? pendingBuffer}) {
    return MarkdownStreamCollectorState(
      pendingBuffer: pendingBuffer ?? this.pendingBuffer,
    );
  }
}

class MarkdownStreamPushResult {
  const MarkdownStreamPushResult({
    required this.state,
    required this.completedLines,
  });

  final MarkdownStreamCollectorState state;
  final List<String> completedLines;
}

class MarkdownStreamFinalizeResult {
  const MarkdownStreamFinalizeResult({
    required this.state,
    required this.completedLines,
  });

  final MarkdownStreamCollectorState state;
  final List<String> completedLines;
}

MarkdownStreamPushResult pushMarkdownDelta(
  MarkdownStreamCollectorState state,
  String delta,
) {
  if (delta.isEmpty) {
    return MarkdownStreamPushResult(state: state, completedLines: const []);
  }

  final merged = '${state.pendingBuffer}$delta'
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final lastNewline = merged.lastIndexOf('\n');
  if (lastNewline == -1) {
    return MarkdownStreamPushResult(
      state: state.copyWith(pendingBuffer: merged),
      completedLines: const [],
    );
  }

  final completePart = merged.substring(0, lastNewline + 1);
  final pending = merged.substring(lastNewline + 1);
  final lines = _nonEmptyLines(completePart.split('\n'));
  return MarkdownStreamPushResult(
    state: state.copyWith(pendingBuffer: pending),
    completedLines: lines,
  );
}

MarkdownStreamFinalizeResult finalizeMarkdownStream(
  MarkdownStreamCollectorState state,
) {
  final pending = state.pendingBuffer.trimRight();
  if (pending.isEmpty) {
    return const MarkdownStreamFinalizeResult(
      state: MarkdownStreamCollectorState(),
      completedLines: <String>[],
    );
  }
  return MarkdownStreamFinalizeResult(
    state: const MarkdownStreamCollectorState(),
    completedLines: <String>[pending],
  );
}

List<String> _nonEmptyLines(List<String> lines) {
  final out = <String>[];
  for (final line in lines) {
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) {
      continue;
    }
    out.add(trimmed);
  }
  return out;
}
