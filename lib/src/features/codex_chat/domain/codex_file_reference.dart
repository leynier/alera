final RegExp _codexFileReferenceWhitespace = RegExp(r'\s');

String codexFileReferenceText(String path) {
  final trimmed = path.trim();
  if (_codexFileReferenceWhitespace.hasMatch(trimmed) &&
      !trimmed.contains('"')) {
    return '"$trimmed"';
  }
  return trimmed;
}

({int start, int end})? codexFileReferenceRange(
  String text,
  String token, {
  int? preferredStart,
}) {
  if (token.isEmpty) return null;
  final candidates = <int>[];
  var offset = 0;
  while (offset <= text.length - token.length) {
    final index = text.indexOf(token, offset);
    if (index < 0) break;
    candidates.add(index);
    offset = index + token.length;
  }
  if (candidates.isEmpty) return null;
  final start = preferredStart == null
      ? candidates.first
      : candidates.reduce(
          (closest, candidate) =>
              (candidate - preferredStart).abs() <
                  (closest - preferredStart).abs()
              ? candidate
              : closest,
        );
  final tokenEnd = start + token.length;
  return (
    start: start,
    end: tokenEnd < text.length && text[tokenEnd] == ' '
        ? tokenEnd + 1
        : tokenEnd,
  );
}
