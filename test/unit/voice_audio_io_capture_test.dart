import 'dart:async';
import 'dart:typed_data';

import 'package:alera/src/features/voice/infra/voice_audio_io.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  test('stop during startStream closes the recorder once it opens', () async {
    final recorder = _FakeRecorder();
    final audio = VoiceAudioIo(_NoopRunner(), createRecorder: () => recorder);

    final starting = audio.startCapture();
    await pumpEventQueue();
    expect(recorder.startCalls, 1);

    await audio.stopCapture();
    final stopsBeforeOpen = recorder.stopCalls;
    recorder.open();
    await starting;

    expect(recorder.stopCalls, stopsBeforeOpen + 1);
    expect(recorder.controller.hasListener, isFalse);
  });

  test('a stale start does not stop a newer capture', () async {
    final recorder = _FakeRecorder();
    final audio = VoiceAudioIo(_NoopRunner(), createRecorder: () => recorder);

    final stale = audio.startCapture();
    await pumpEventQueue();
    await audio.stopCapture();
    final fresh = audio.startCapture();
    await pumpEventQueue();
    expect(recorder.startCalls, 2);
    final stopsBeforeOpen = recorder.stopCalls;

    recorder.open();
    await Future.wait(<Future<void>>[stale, fresh]);

    expect(recorder.stopCalls, stopsBeforeOpen);
    expect(recorder.controller.hasListener, isTrue);
    await audio.stopCapture();
    expect(recorder.controller.hasListener, isFalse);
  });

  test('an uninterrupted start listens to the stream', () async {
    final recorder = _FakeRecorder();
    final audio = VoiceAudioIo(_NoopRunner(), createRecorder: () => recorder);

    final starting = audio.startCapture();
    await pumpEventQueue();
    recorder.open();
    await starting;

    expect(recorder.controller.hasListener, isTrue);
    expect(recorder.stopCalls, 0);
    await audio.stopCapture();
    expect(recorder.stopCalls, 1);
  });
}

class _FakeRecorder implements AudioRecorder {
  final controller = StreamController<Uint8List>.broadcast();
  final _opens = <Completer<Stream<Uint8List>>>[];
  var startCalls = 0;
  var stopCalls = 0;

  void open() {
    for (final pending in _opens) {
      pending.complete(controller.stream);
    }
    _opens.clear();
  }

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopRunner implements ProcessRunner {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
