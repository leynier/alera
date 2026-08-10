final RegExp _mobileCodexFileReferenceWhitespace = RegExp(r'\s');

String mobileCodexFileReferenceText(String path) {
  final trimmed = path.trim();
  if (_mobileCodexFileReferenceWhitespace.hasMatch(trimmed) &&
      !trimmed.contains('"')) {
    return '"$trimmed"';
  }
  return trimmed;
}

({int start, int end})? mobileCodexFileReferenceRange(
  String text,
  String path,
) {
  final reference = mobileCodexFileReferenceText(path);
  if (reference.isEmpty) return null;
  var offset = 0;
  while (offset <= text.length - reference.length) {
    final start = text.indexOf(reference, offset);
    if (start < 0) return null;
    final end = start + reference.length;
    final before = start == 0 ? null : text[start - 1];
    final after = end == text.length ? null : text[end];
    if ((before == null || before.trim().isEmpty) &&
        (after == null || after.trim().isEmpty)) {
      return (start: start, end: end);
    }
    offset = start + 1;
  }
  return null;
}

bool mobileCodexIsAudioFile(String path, [String? mimeType]) {
  if (mimeType?.toLowerCase().startsWith('audio/') == true) return true;
  final lower = path.toLowerCase();
  return const <String>[
    '.mp3',
    '.m4a',
    '.wav',
    '.ogg',
    '.flac',
    '.aac',
    '.opus',
  ].any(lower.endsWith);
}
