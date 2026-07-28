const int aleraBrowserTitleMaximumBytes = 1024;

String normalizeAleraBrowserTitle(String value) {
  final output = StringBuffer();
  final pendingWhitespace = <int>[];
  var outputBytes = 0;
  var pendingBytes = 0;
  var pendingOverflow = false;

  for (final rune in value.runes) {
    if (_isControlRune(rune)) {
      continue;
    }
    if (_isTrimWhitespace(rune)) {
      if (outputBytes == 0) {
        continue;
      }
      final byteCount = _utf8ByteCount(rune);
      if (!pendingOverflow &&
          outputBytes + pendingBytes + byteCount <=
              aleraBrowserTitleMaximumBytes) {
        pendingWhitespace.add(rune);
        pendingBytes += byteCount;
      } else {
        pendingOverflow = true;
      }
      continue;
    }
    final byteCount = _utf8ByteCount(rune);
    if (pendingOverflow ||
        outputBytes + pendingBytes + byteCount >
            aleraBrowserTitleMaximumBytes) {
      break;
    }
    for (final whitespace in pendingWhitespace) {
      output.writeCharCode(whitespace);
    }
    outputBytes += pendingBytes;
    pendingWhitespace.clear();
    pendingBytes = 0;
    output.writeCharCode(rune);
    outputBytes += byteCount;
  }
  return output.toString();
}

bool _isControlRune(int rune) => rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f);

bool _isTrimWhitespace(int rune) =>
    rune == 0x20 ||
    rune == 0xa0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200a) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202f ||
    rune == 0x205f ||
    rune == 0x3000 ||
    rune == 0xfeff;

int _utf8ByteCount(int rune) {
  if (rune <= 0x7f) {
    return 1;
  }
  if (rune <= 0x7ff) {
    return 2;
  }
  if (rune <= 0xffff) {
    return 3;
  }
  return 4;
}
