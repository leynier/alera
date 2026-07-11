part of 'terminal_runtime.dart';

int _terminalOutputFrameCutoff(String value) {
  if (value.length <= _terminalOutputMaxCharsPerFrame) {
    return value.length;
  }
  var cutoff = _terminalOutputMaxCharsPerFrame;
  final codeUnit = value.codeUnitAt(cutoff);
  if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
    cutoff -= 1;
  }
  return cutoff;
}

const int _terminalOutputMaxCharsPerFrame = 64 * 1024;
