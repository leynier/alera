import 'package:alera/src/features/session/application/streaming/markdown_stream_collector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('markdown stream collector', () {
    test('does not soft-flush when pending text is too fresh and short', () {
      final now = DateTime.utc(2026, 2, 22, 4, 0, 0);
      final state = MarkdownStreamCollectorState(
        pendingBuffer: 'short pending text',
        pendingSince: now,
      );

      final result = maybeFlushSoftChunk(state, now: now);
      expect(result.chunk, isNull);
      expect(result.state.pendingBuffer, state.pendingBuffer);
      expect(result.state.pendingSince, state.pendingSince);
    });

    test('soft-flushes by age when pending text is long enough', () {
      final now = DateTime.utc(2026, 2, 22, 4, 0, 0);
      final state = MarkdownStreamCollectorState(
        pendingBuffer:
            'Este texto final no tiene salto de linea pero debe fluir de forma natural para verse mejor.',
        pendingSince: now.subtract(const Duration(milliseconds: 250)),
      );

      final result = maybeFlushSoftChunk(state, now: now);
      expect(result.chunk, isNotNull);
      expect(result.chunk!.length, greaterThanOrEqualTo(32));
      expect(
        result.state.pendingBuffer.length,
        lessThan(state.pendingBuffer.length),
      );
    });

    test('soft-flushes by size even if age is low', () {
      final now = DateTime.utc(2026, 2, 22, 4, 0, 0);
      final state = MarkdownStreamCollectorState(
        pendingBuffer:
            'uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce quince dieciseis diecisiete dieciocho',
        pendingSince: now,
      );

      final result = maybeFlushSoftChunk(state, now: now);
      expect(result.chunk, isNotNull);
      expect(
        result.state.pendingBuffer.length,
        lessThan(state.pendingBuffer.length),
      );
    });

    test('uses hard max when there are no natural boundaries', () {
      final now = DateTime.utc(2026, 2, 22, 4, 0, 0);
      final state = MarkdownStreamCollectorState(
        pendingBuffer: List<String>.filled(220, 'a').join(),
        pendingSince: now.subtract(const Duration(milliseconds: 250)),
      );

      final result = maybeFlushSoftChunk(state, now: now);
      expect(result.chunk, isNotNull);
      expect(result.chunk!.length, 180);
      expect(result.state.pendingBuffer.length, 40);
    });

    test('does not soft-flush with an open markdown code fence', () {
      final now = DateTime.utc(2026, 2, 22, 4, 0, 0);
      final state = MarkdownStreamCollectorState(
        pendingBuffer:
            '```dart\nvoid main() {\n  print("hello");\n}\ntexto fuera del fence',
        pendingSince: now.subtract(const Duration(milliseconds: 300)),
      );

      final result = maybeFlushSoftChunk(state, now: now);
      expect(result.chunk, isNull);
      expect(result.state.pendingBuffer, state.pendingBuffer);
    });
  });
}
