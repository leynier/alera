import 'dart:collection';

import 'package:alera_mobile/src/features/terminal/domain/terminal_output_batcher.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_restore_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The batcher schedules frame callbacks, so the binding has to exist even
  // though these tests drive flushes by hand.
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> writes;

  TerminalOutputBatcher batcher({int maxCharsPerFrame = 1024}) {
    final subject = TerminalOutputBatcher(
      write: writes.add,
      maxCharsPerFrame: maxCharsPerFrame,
      maxPendingChars: 4096,
    );
    addTearDown(subject.dispose);
    return subject;
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

  test('a partial drain retains the original chunk and advances its head', () {
    final subject = batcher(maxCharsPerFrame: 10);
    final original = 'a' * 25;

    subject.add(original);
    subject.flushFrame();

    expect(subject.debugPendingHeadStorage, same(original));
    expect(subject.debugPendingHeadOffset, 10);
  });

  test(
    'sustained output waits for the cadence floor after its first frame',
    () async {
      final frames = Queue<void Function()>();
      final subject = TerminalOutputBatcher(
        write: writes.add,
        minFlushInterval: const Duration(milliseconds: 50),
        scheduleFrame: frames.add,
      );
      addTearDown(subject.dispose);

      subject.add('first');
      expect(frames, hasLength(1));
      frames.removeFirst()();

      subject.add('second');
      expect(subject.debugFlushDeferred, isTrue);
      expect(frames, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(subject.debugFlushDeferred, isFalse);
      expect(frames, hasLength(1));
      frames.removeFirst()();
      expect(writes, <String>['first', 'second']);
    },
  );

  test('a runaway process cannot grow the backlog without bound', () {
    final subject = TerminalOutputBatcher(
      write: writes.add,
      maxCharsPerFrame: 100,
      maxPendingChars: 50,
    );
    addTearDown(subject.dispose);

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
    addTearDown(subject.dispose);

    subject.addSnapshot('y' * 300);

    expect(subject.pendingChars, 300);
  });

  test('live backlog trimming never discards a restore snapshot', () {
    final subject = TerminalOutputBatcher(
      write: writes.add,
      maxCharsPerFrame: 1000,
      maxPendingChars: 50,
    );
    addTearDown(subject.dispose);

    subject.addSnapshot('s' * 300);
    subject.add('l' * 120);

    expect(subject.pendingChars, 350);
    while (subject.pendingChars > 0) {
      subject.flushFrame();
    }
    expect(writes.join(), '${'s' * 300}${'l' * 50}');
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

  group('restore progress', () {
    late List<TerminalRestoreProgress?> reported;

    TerminalOutputBatcher restoring({int maxCharsPerFrame = 100}) {
      final subject = TerminalOutputBatcher(
        write: writes.add,
        onRestoreProgress: reported.add,
        maxCharsPerFrame: maxCharsPerFrame,
        maxPendingChars: 4096,
      );
      addTearDown(subject.dispose);
      return subject;
    }

    setUp(() => reported = <TerminalRestoreProgress?>[]);

    test('is reported before the first frame draws any of the snapshot', () {
      // The cover has to be up before the emulator is written to, or the first
      // 64 KB of history is already on screen when it appears.
      final subject = restoring();

      subject.addSnapshot('s' * 250);

      expect(writes, isEmpty);
      expect(reported.single?.totalChars, 250);
      expect(reported.single?.writtenChars, 0);
    });

    test('advances per frame and clears once the snapshot is fully in', () {
      final subject = restoring();

      subject.addSnapshot('s' * 250);
      subject.flushFrame();
      subject.flushFrame();
      subject.flushFrame();

      expect(reported.map((progress) => progress?.writtenChars), <int?>[
        0,
        100,
        200,
        null,
      ]);
      expect(subject.debugRestoring, isFalse);
    });

    test('live output queued behind a restore does not hold the cover up', () {
      // The cover is for the history replay. Output that arrived while it
      // drained is ordinary live output and must not extend the wait.
      final subject = restoring();

      subject.addSnapshot('s' * 100);
      subject.add('l' * 500);
      subject.flushFrame();

      expect(reported.last, isNull);
      expect(subject.pendingChars, 500);
    });

    test('a batcher discarded mid-restore takes its own cover down', () {
      // Replacing the emulator disposes the batcher; nothing else would clear
      // a progress value left behind, and the cover would never lift.
      final subject = restoring();

      subject.addSnapshot('s' * 250);
      subject.dispose();

      expect(reported.last, isNull);
    });

    test('a batcher that never restored reports nothing on dispose', () {
      final subject = restoring();

      subject.add('live');
      subject.flushFrame();
      subject.dispose();

      expect(reported, isEmpty);
    });
  });
}
