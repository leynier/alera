import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/features/terminal/domain/terminal_snapshot_payload.dart';
import 'package:flutter_test/flutter_test.dart';

class _Recorder {
  final List<String> writes = <String>[];
  final List<int> pending = <int>[];
  final Completer<void> restored = Completer<void>();

  late final TerminalSnapshotGate gate = TerminalSnapshotGate(
    restore: (text, cols, rows) {
      writes.add('restore:$text@$cols');
      if (!restored.isCompleted) {
        restored.complete();
      }
    },
    live: (text) => writes.add('live:$text'),
    pending: pending.add,
  );
}

TerminalSnapshotPayload _large(String prefix) => TerminalSnapshotPayload.base64(
  base64Encode(
    utf8.encode('$prefix${'x' * terminalSnapshotInlineDecodeLimit}'),
  ),
);

void main() {
  test('a small snapshot restores in place', () {
    final recorder = _Recorder();

    recorder.gate.begin(
      TerminalSnapshotPayload.base64(base64Encode(utf8.encode('hi → ñ'))),
      cols: 120,
    );
    recorder.gate.addLive('after');

    expect(recorder.writes, <String>['restore:hi → ñ@120', 'live:after']);
    expect(recorder.pending, isEmpty);
  });

  test('live output waits behind a snapshot decoding off-isolate', () async {
    final recorder = _Recorder();

    recorder.gate.begin(_large('big'), cols: 200);
    recorder.gate.addLive('one');
    recorder.gate.addLive('two');

    // Nothing reaches the emulator until the snapshot that it follows.
    expect(recorder.writes, isEmpty);
    expect(recorder.pending.single, greaterThan(0));
    expect(recorder.gate.debugHoldingLiveOutput, isTrue);

    await recorder.restored.future;

    expect(recorder.writes, hasLength(3));
    expect(recorder.writes[0], startsWith('restore:bigxxx'));
    expect(recorder.writes[0], endsWith('@200'));
    expect(recorder.writes.sublist(1), <String>['live:one', 'live:two']);
    expect(recorder.gate.debugHoldingLiveOutput, isFalse);
  });

  test('a newer snapshot supersedes one still decoding', () async {
    final recorder = _Recorder();

    recorder.gate.begin(_large('stale'));
    recorder.gate.addLive('belongs to the stale snapshot');
    recorder.gate.begin(
      TerminalSnapshotPayload.base64(base64Encode(utf8.encode('fresh'))),
    );
    recorder.gate.addLive('live');
    // Long enough for the stale worker to have answered.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(recorder.writes, <String>['restore:fresh@null', 'live:live']);
  });

  test('a snapshot that will not decode still releases live output', () async {
    final recorder = _Recorder();

    recorder.gate.begin(
      TerminalSnapshotPayload.base64(
        '!' * (terminalSnapshotInlineDecodeLimit + 1),
      ),
    );
    recorder.gate.addLive('still shown');
    await recorder.restored.future;
    await pumpEventQueue();

    expect(recorder.writes, <String>['restore:@null', 'live:still shown']);
  });

  test('cancel drops a snapshot still decoding', () async {
    final recorder = _Recorder();

    recorder.gate.begin(_large('gone'));
    recorder.gate.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(recorder.writes, isEmpty);
  });
}
