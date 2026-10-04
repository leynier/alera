import 'dart:convert';

/// Decodes one session's live PTY output across chunks.
///
/// The host sends raw bytes as the PTY produced them, so a multi-byte
/// character can be split between two output messages. Decoding each message
/// on its own turned both halves into U+FFFD, which is how box-drawing and
/// other non-ASCII glyphs in a TUI came out broken. The desktop keeps one
/// chunked decoder per session for the same reason.
class TerminalUtf8Stream {
  final StringBuffer _decoded = StringBuffer();
  late ByteConversionSink _sink = _open();

  /// Text for [bytes], holding back a trailing partial character until the
  /// bytes that complete it arrive.
  String decode(List<int> bytes) {
    _sink.add(bytes);
    if (_decoded.isEmpty) {
      return '';
    }
    final text = _decoded.toString();
    _decoded.clear();
    return text;
  }

  /// Drops any partial character, for when the stream restarts from a
  /// snapshot and the held bytes no longer have a continuation.
  void reset() {
    _decoded.clear();
    _sink = _open();
  }

  ByteConversionSink _open() => const Utf8Decoder(allowMalformed: true)
      .startChunkedConversion(StringConversionSink.fromStringSink(_decoded));
}
