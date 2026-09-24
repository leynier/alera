import 'dart:async';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/voice/infra/mobile_voice_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  test('a start invalidated during startStream closes the recorder', () async {
    final recorder = _FakeRecorder();
    final capture = MobileVoiceCapture(createRecorder: () => recorder);
    var valid = true;

    final starting = capture.start((_) {}, stillValid: () => valid);
    await pumpEventQueue();
    expect(recorder.startCalls, 1);

    valid = false;
    await capture.stop();
    final stopsBeforeOpen = recorder.stopCalls;
    recorder.open();
    await starting;

    expect(recorder.stopCalls, stopsBeforeOpen + 1);
    expect(recorder.controller.hasListener, isFalse);
  });

  test('a stale start does not stop a newer capture', () async {
    final recorder = _FakeRecorder();
    final capture = MobileVoiceCapture(createRecorder: () => recorder);
    var epoch = 1;

    final stale = capture.start((_) {}, stillValid: () => epoch == 1);
    await pumpEventQueue();
    epoch = 2;
    final fresh = capture.start((_) {}, stillValid: () => epoch == 2);
    await pumpEventQueue();
    expect(recorder.startCalls, 2);

    recorder.open();
    await Future.wait(<Future<void>>[stale, fresh]);

    expect(recorder.stopCalls, 0);
    expect(recorder.controller.hasListener, isTrue);
    await capture.stop();
    expect(recorder.controller.hasListener, isFalse);
    expect(recorder.stopCalls, 1);
  });

  test('forwards PCM chunks and disposes the recorder', () async {
    final recorder = _FakeRecorder();
    final capture = MobileVoiceCapture(createRecorder: () => recorder);
    final chunks = <Uint8List>[];

    final starting = capture.start(chunks.add, stillValid: () => true);
    await pumpEventQueue();
    recorder.open();
    await starting;
    recorder.controller.add(Uint8List.fromList(<int>[1, 2]));
    await pumpEventQueue();

    expect(chunks, hasLength(1));
    await capture.dispose();
    expect(recorder.disposed, isTrue);
    expect(recorder.controller.hasListener, isFalse);
  });

  test('requires microphone permission', () async {
    final recorder = _FakeRecorder()..permitted = false;
    final capture = MobileVoiceCapture(createRecorder: () => recorder);

    await expectLater(
      capture.start((_) {}, stillValid: () => true),
      throwsStateError,
    );
    expect(recorder.startCalls, 0);
  });
}

class _FakeRecorder implements AudioRecorder {
  final controller = StreamController<Uint8List>.broadcast();
  final _opens = <Completer<Stream<Uint8List>>>[];
  var permitted = true;
  var startCalls = 0;
  var stopCalls = 0;
  var disposed = false;

  void open() {
    for (final pending in _opens) {
      pending.complete(controller.stream);
    }
    _opens.clear();
  }

  @override
  Future<bool> hasPermission({bool request = true}) async => permitted;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) {
    startCalls += 1;
    final pending = Completer<Stream<Uint8List>>();
    _opens.add(pending);
    return pending.future;
  }

  @override
  Future<String?> stop() async {
    stopCalls += 1;
    return null;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
