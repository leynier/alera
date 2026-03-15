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

    test('pushMarkdownDelta does not emit trailing empty line from split', () {
      final now = DateTime.utc(2026, 2, 22, 4, 0, 0);
      const state = MarkdownStreamCollectorState();
      final r1 = pushMarkdownDelta(state, '| Mes | Ventas |\n', now: now);
      expect(r1.completedLines, ['| Mes | Ventas |']);
      final r2 = pushMarkdownDelta(r1.state, '|---|---|\n', now: now);
      expect(r2.completedLines, ['|---|---|']);
      final r3 = pushMarkdownDelta(r2.state, '| Enero | \$12,500 |\n', now: now);
      expect(r3.completedLines, ['| Enero | \$12,500 |']);
    });

    test('pushMarkdownDelta preserves paragraph breaks from double newline', () {
      final now = DateTime.utc(2026, 2, 22, 4, 0, 0);
      const state = MarkdownStreamCollectorState();
      final r = pushMarkdownDelta(state, '| Marzo |\n\n', now: now);
      expect(r.completedLines, ['| Marzo |', '']);
    });

    test('does not soft-flush a table row to prevent breaking table syntax', () {
      final now = DateTime.utc(2026, 2, 22, 4, 0, 0);
      final state = MarkdownStreamCollectorState(
        pendingBuffer:
            '| Diseño | Completado | Interfaz principal aprobada |',
        pendingSince: now.subtract(const Duration(milliseconds: 300)),
      );
      final result = maybeFlushSoftChunk(state, now: now);
      expect(result.chunk, isNull);
      expect(result.state.pendingBuffer, state.pendingBuffer);
    });

    test('does not soft-flush a table separator row', () {
      final now = DateTime.utc(2026, 2, 22, 4, 0, 0);
      final state = MarkdownStreamCollectorState(
        pendingBuffer: '|---|---:|---:|',
        pendingSince: now.subtract(const Duration(milliseconds: 300)),
      );
      final result = maybeFlushSoftChunk(state, now: now);
      expect(result.chunk, isNull);
    });

    test('streaming table rows produce contiguous lines for markdown parsing', () {
      final now = DateTime.utc(2026, 2, 22, 4, 0, 0);
      const state = MarkdownStreamCollectorState();
      final deltas = [
        '| Mes | Ventas |\n',
        '|---|---|\n',
        '| Enero | \$12,500 |\n',
        '| Febrero | \$14,200 |\n',
      ];
      var collector = state;
      final allLines = <String>[];
      for (final delta in deltas) {
        final r = pushMarkdownDelta(collector, delta, now: now);
        collector = r.state;
        allLines.addAll(r.completedLines);
      }
      // Table rows should be contiguous with no empty lines between them
      expect(allLines, [
        '| Mes | Ventas |',
        '|---|---|',
        '| Enero | \$12,500 |',
        '| Febrero | \$14,200 |',
      ]);
      // Simulate assembly: consecutive non-empty lines get \n between them
      final buf = StringBuffer(allLines.first);
      for (var i = 1; i < allLines.length; i++) {
        if (allLines[i].isEmpty) {
          buf.write('\n\n');
        } else {
          buf.write('\n');
          buf.write(allLines[i]);
        }
      }
      final assembled = buf.toString();
      expect(
        assembled,
        '| Mes | Ventas |\n'
        '|---|---|\n'
        '| Enero | \$12,500 |\n'
        '| Febrero | \$14,200 |',
      );
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
