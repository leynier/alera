final RegExp _mobileCodexFileReferenceWhitespace = RegExp(r'\s');

String mobileCodexFileReferenceText(String path) {
  final trimmed = path.trim();
  if (_mobileCodexFileReferenceWhitespace.hasMatch(trimmed) &&
      !trimmed.contains('"')) {
    return '"$trimmed"';
  }
  return trimmed;
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
