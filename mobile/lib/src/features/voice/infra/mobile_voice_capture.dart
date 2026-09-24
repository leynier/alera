import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Owns the microphone recorder and its PCM subscription for the mobile voice
/// session. A start that loses a race with stop never leaves the recorder
/// streaming.
class MobileVoiceCapture {
  MobileVoiceCapture({AudioRecorder Function()? createRecorder})
    : _createRecorder = createRecorder ?? AudioRecorder.new;

  final AudioRecorder Function() _createRecorder;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _frames;
  var _claim = 0;

  /// Opens the microphone and forwards PCM16 16 kHz mono chunks to [onBytes].
  /// When [stillValid] turns false while the recorder is starting, the
  /// recorder is stopped again unless a newer [start] already claimed it.
  Future<void> start(
    void Function(Uint8List chunk) onBytes, {
    required bool Function() stillValid,
  }) async {
    final recorder = _recorder ??= _createRecorder();
    if (!await recorder.hasPermission()) {
      throw StateError('Microphone permission is required for voice.');
    }
    if (!stillValid()) {
      return;
    }
    final claim = ++_claim;
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    if (!stillValid() || claim != _claim) {
      await _release(recorder, claim);
      return;
    }
    final previous = _frames;
    _frames = null;
    await previous?.cancel();
    if (!stillValid() || claim != _claim) {
      await _release(recorder, claim);
      return;
    }
    _frames = stream.listen(onBytes);
  }

  /// Cancels the PCM subscription and stops the recorder.
  Future<void> stop() async {
    final frames = _frames;
    _frames = null;
    try {
      await frames?.cancel();
    } on Object {
      // Frame cancellation must not skip recorder stop.
    }
    await _recorder?.stop();
  }

  Future<void> dispose() async {
    try {
      await stop();
    } on Object {
      // Recorder stop must not skip recorder dispose.
    }
    try {
      await _recorder?.dispose();
    } finally {
      _recorder = null;
    }
  }

  Future<void> _release(AudioRecorder recorder, int claim) async {
    if (claim != _claim) {
      return;
    }
    try {
      await recorder.stop();
    } on Object {
      // Best-effort close of a start that lost the race with stop.
    }
  }
}
