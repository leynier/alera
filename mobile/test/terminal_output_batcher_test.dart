import 'package:alera_mobile/src/features/terminal/domain/terminal_output_batcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The batcher schedules frame callbacks, so the binding has to exist even
  // though these tests drive flushes by hand.
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> writes;

  TerminalOutputBatcher batcher({int maxCharsPerFrame = 1024}) {
    return TerminalOutputBatcher(
      write: writes.add,
      maxCharsPerFrame: maxCharsPerFrame,
      maxPendingChars: 4096,
    );
  }

  setUp(() => writes = <String>[]);

  test('a burst of chunks becomes one write per frame', () {
    // The behaviour that matters: without this each chunk parsed and repainted
    // on its own inside the same frame.
    final subject = batcher();

    for (var i = 0; i < 20; i++) {
      subject.add('chunk-$i ');
    }
    subject.flushFrame();

    expect(writes, hasLength(1));
    expect(writes.single, startsWith('chunk-0 '));
    expect(writes.single, endsWith('chunk-19 '));
  });

  test('output past the frame budget carries into the next frame', () {
    final subject = batcher(maxCharsPerFrame: 10);

    subject.add('a' * 25);
    subject.flushFrame();
    expect(writes, hasLength(1));
    expect(writes.single.length, 10);

    subject.flushFrame();
    subject.flushFrame();

    expect(writes.map((write) => write.length), <int>[10, 10, 5]);
    expect(writes.join(), 'a' * 25);
  });

  test('a runaway process cannot grow the backlog without bound', () {
    final subject = TerminalOutputBatcher(
      write: writes.add,
      maxCharsPerFrame: 100,
      maxPendingChars: 50,
    );

    for (var i = 0; i < 10; i++) {
      subject.add('x' * 30);
    }

    expect(subject.pendingChars, lessThanOrEqualTo(50));
  });

  test('a snapshot is exempt from the backlog cap', () {
    // It is a bounded one-shot payload, so trimming it would silently drop
    // restored history.
    final subject = TerminalOutputBatcher(
      write: writes.add,
      maxCharsPerFrame: 1000,
      maxPendingChars: 50,
    );

    subject.addSnapshot('y' * 300);

    expect(subject.pendingChars, 300);
  });

  test('never splits a surrogate pair across frames', () {
    final subject = batcher(maxCharsPerFrame: 3);
    // Two UTF-16 code units each.
    const emoji = '😀😀';

    subject.add('ab$emoji');
    subject.flushFrame();
    subject.flushFrame();
    subject.flushFrame();

    expect(writes.join(), 'ab$emoji');
    for (final write in writes) {
      expect(
        write.runes.any((rune) => rune >= 0xD800 && rune <= 0xDFFF),
        isFalse,
        reason: 'a half surrogate would render as a broken glyph',
      );
    }
  });

  test('empty input is ignored', () {
    final subject = batcher();

    subject.add('');
    subject.flushFrame();

    expect(writes, isEmpty);
  });

  test('dispose drops pending output', () {
    final subject = batcher();

    subject.add('pending');
    subject.dispose();
    subject.flushFrame();

    expect(writes, isEmpty);
    expect(subject.pendingChars, 0);
  });
}
