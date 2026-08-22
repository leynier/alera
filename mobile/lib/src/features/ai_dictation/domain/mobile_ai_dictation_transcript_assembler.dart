class MobileAiDictationTranscriptAssembler {
  final _parts = <String>[];

  String get text => _parts.join(' ').trim();

  String get prompt {
    final value = text;
    if (value.length <= 240) return value;
    return value.substring(value.length - 240);
  }

  void add(String rawPart) {
    final part = rawPart.trim();
    if (part.isEmpty) return;
    if (_parts.isEmpty) {
      _parts.add(part);
      return;
    }

    final previousWords = _parts.last.split(RegExp(r'\s+'));
    final nextWords = part.split(RegExp(r'\s+'));
    final overlap = _overlap(previousWords, nextWords);
    final remainder = nextWords.skip(overlap).join(' ').trim();
    if (remainder.isNotEmpty) _parts.add(remainder);
  }

  int _overlap(List<String> previous, List<String> next) {
    final maximum = previous.length < next.length
        ? previous.length
        : next.length;
    final limit = maximum.clamp(0, 12).toInt();
    for (var count = limit; count > 0; count--) {
      final previousSlice = previous
          .sublist(previous.length - count)
          .map(_normalize)
          .join(' ');
      final nextSlice = next.sublist(0, count).map(_normalize).join(' ');
      if (previousSlice == nextSlice) return count;
    }
    return 0;
  }

  String _normalize(String word) => word.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
    '',
  );
}
