class MarkdownStreamCollectorState {
  const MarkdownStreamCollectorState({
    this.pendingBuffer = '',
    this.pendingSince,
  });

  final String pendingBuffer;
  final DateTime? pendingSince;

  MarkdownStreamCollectorState copyWith({
    String? pendingBuffer,
    DateTime? pendingSince,
    bool clearPendingSince = false,
  }) {
    return MarkdownStreamCollectorState(
      pendingBuffer: pendingBuffer ?? this.pendingBuffer,
      pendingSince: clearPendingSince
          ? null
          : (pendingSince ?? this.pendingSince),
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

class MarkdownStreamSoftFlushResult {
  const MarkdownStreamSoftFlushResult({required this.state, this.chunk});

  final MarkdownStreamCollectorState state;
  final String? chunk;
}

MarkdownStreamPushResult pushMarkdownDelta(
  MarkdownStreamCollectorState state,
  String delta,
  {
  required DateTime now,
}
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
      state: state.copyWith(
        pendingBuffer: merged,
        pendingSince: state.pendingSince ?? now,
      ),
      completedLines: const [],
    );
  }

  final completePart = merged.substring(0, lastNewline + 1);
  final pending = merged.substring(lastNewline + 1);
  final lines = _trimmedLines(completePart.split('\n'));
  // split() on a string ending with \n always produces a trailing empty
  // element.  Remove it so the assembly loop does not insert a spurious
  // paragraph break (\n\n) after every single line.
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return MarkdownStreamPushResult(
    state: state.copyWith(
      pendingBuffer: pending,
      pendingSince: pending.isEmpty ? null : now,
      clearPendingSince: pending.isEmpty,
    ),
    completedLines: lines,
  );
}

MarkdownStreamSoftFlushResult maybeFlushSoftChunk(
  MarkdownStreamCollectorState state, {
  required DateTime now,
  int softFlushMaxPendingAgeMs = 180,
  int softFlushTargetChars = 96,
  int softFlushMinChars = 32,
  int softFlushHardMaxChars = 180,
}) {
  final buffer = state.pendingBuffer;
  if (buffer.isEmpty) {
    return MarkdownStreamSoftFlushResult(state: state);
  }
  if (_hasOpenCodeFence(buffer) || _looksLikeTableRow(buffer)) {
    return MarkdownStreamSoftFlushResult(state: state);
  }

  final ageMs = state.pendingSince == null
      ? 0
      : now.difference(state.pendingSince!).inMilliseconds;
  final shouldFlushByAge = ageMs >= softFlushMaxPendingAgeMs;
  final shouldFlushBySize = buffer.length >= softFlushTargetChars;
  if (!shouldFlushByAge && !shouldFlushBySize) {
    return MarkdownStreamSoftFlushResult(state: state);
  }

  final splitIndex = _pickSoftSplitIndex(
    buffer,
    targetChars: softFlushTargetChars,
    minChars: softFlushMinChars,
    hardMaxChars: softFlushHardMaxChars,
  );
  if (splitIndex == null || splitIndex <= 0) {
    return MarkdownStreamSoftFlushResult(state: state);
  }

  final chunk = buffer.substring(0, splitIndex);
  if (chunk.trim().isEmpty) {
    return MarkdownStreamSoftFlushResult(state: state);
  }

  final remaining = buffer.substring(splitIndex);
  return MarkdownStreamSoftFlushResult(
    state: state.copyWith(
      pendingBuffer: remaining,
      pendingSince: remaining.isEmpty ? null : now,
      clearPendingSince: remaining.isEmpty,
    ),
    chunk: chunk,
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

int? _pickSoftSplitIndex(
  String text, {
  required int targetChars,
  required int minChars,
  required int hardMaxChars,
}) {
  if (text.isEmpty || text.length < minChars) {
    return null;
  }
  final preferredUpper = text.length < targetChars ? text.length : targetChars;
  final maxUpper = text.length < hardMaxChars ? text.length : hardMaxChars;
  final searchUpper = preferredUpper < maxUpper ? preferredUpper : maxUpper;

  for (var i = searchUpper - 1; i >= minChars - 1; i--) {
    if (_isNaturalBoundary(text.codeUnitAt(i))) {
      return i + 1;
    }
  }

  if (text.length >= hardMaxChars) {
    return hardMaxChars;
  }
  return null;
}

bool _isNaturalBoundary(int codeUnit) {
  return codeUnit == 0x20 || // space
      codeUnit == 0x2E || // .
      codeUnit == 0x2C || // ,
      codeUnit == 0x3B || // ;
      codeUnit == 0x3A || // :
      codeUnit == 0x21 || // !
      codeUnit == 0x3F; // ?
}

// Table rows start with | and must stay intact for the markdown parser.
// Splitting mid-row (like code fences) would break table rendering.
bool _looksLikeTableRow(String text) => text.trimLeft().startsWith('|');

bool _hasOpenCodeFence(String text) {
  var index = 0;
  var count = 0;
  while (true) {
    index = text.indexOf('```', index);
    if (index == -1) {
      break;
    }
    count += 1;
    index += 3;
  }
  return count.isOdd;
}

List<String> _trimmedLines(List<String> lines) =>
    lines.map((line) => line.trimRight()).toList();
