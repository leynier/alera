import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:alera/src/features/voice/infra/voice_pcm_player.dart';
import 'package:alera/src/features/voice/infra/voice_private_wav.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:record/record.dart';

class VoicePcmFrame({required this.samples, required this.rms}) {
  final Int16List samples;
  final double rms;
}

/// Microphone capture for chained STT. Playback writes a temp WAV and plays
/// it through the platform audio helper via [ProcessRunner].
class VoiceAudioIo {
  VoiceAudioIo(this._runner, {AudioRecorder Function()? createRecorder})
    : _createRecorder = createRecorder ?? AudioRecorder.new;

  final ProcessRunner _runner;
  final AudioRecorder Function() _createRecorder;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  final _frames = StreamController<VoicePcmFrame>.broadcast();
  StartedProcess? _player;
  final VoicePcmPlayer _pcm = VoicePcmPlayer();
  var _capturing = false;
  var _captureGeneration = 0;
  var _recorderClaim = 0;
  final BytesBuilder _pcmRemainder = BytesBuilder(copy: false);
  var _streaming = false;
  var _playbackToken = 0;

  Stream<VoicePcmFrame> get frames => _frames.stream;

  bool get isStreaming => _streaming;

  Future<bool> hasPermission() async {
    final recorder = _recorder ??= _createRecorder();
    return recorder.hasPermission();
  }

  Future<void> startCapture() async {
    if (_capturing) {
      return;
    }
    final recorder = _recorder ??= _createRecorder();
    final generation = _captureGeneration;
    if (!await recorder.hasPermission()) {
      throw StateError('Microphone permission is required for voice.');
    }
    if (generation != _captureGeneration) {
      return;
    }
    final claim = ++_recorderClaim;
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    if (generation != _captureGeneration) {
      // A stop ran while the recorder was starting, so its recorder.stop()
      // may have landed before the stream opened. Close the microphone here
      // unless a newer start has already claimed the recorder.
      if (claim == _recorderClaim) {
        try {
          await recorder.stop();
        } on Object {
          // Best-effort close of a start that lost the race with stop.
        }
      }
      return;
    }
    _capturing = true;
    _subscription = stream.listen(_onBytes);
  }

  Future<void> stopCapture() async {
    _capturing = false;
    _captureGeneration += 1;
    _pcmRemainder.clear();
    try {
      await _subscription?.cancel();
    } on Object {
      // Subscription cancel must not skip recorder stop.
    }
    _subscription = null;
    try {
      await _recorder?.stop();
    } on Object {
      // Recorder stop must not skip remaining shutdown.
    }
  }

  Future<void> playWav(List<int> bytes) async {
    final token = _playbackToken;
    await stopPlayback();
    final started = token + 1;
    if (bytes.isEmpty || _playbackToken != started) {
      return;
    }
    await _playFileAndWait(await _writeTempWav(bytes), started);
  }

  Future<void> playPcm(List<int> pcm, {required int sampleRate}) async {
    final token = _playbackToken;
    await stopPlayback();
    final started = token + 1;
    if (pcm.isEmpty || _playbackToken != started) {
      return;
    }
    await _playFileAndWait(
      await _writeTempWav(pcm16ToWav(pcm, sampleRate: sampleRate)),
      started,
    );
  }

  Future<void> startPcmStream({required int sampleRate}) async {
    if (_streaming && _pcm.isStreaming) {
      return;
    }
    final token = _playbackToken;
    await stopPlayback();
    final started = token + 1;
    if (_playbackToken != started) {
      return;
    }
    await _pcm.start(sampleRate: sampleRate);
    if (started != _playbackToken) {
      await _pcm.stop();
      return;
    }
    _streaming = _pcm.isStreaming;
  }

  Future<void> writePcm(List<int> pcm) async {
    if (pcm.isEmpty) {
      return;
    }
    _pcm.write(pcm);
  }

  Future<void> finishPcmStream() async {
    _pcm.finish();
    _streaming = false;
    await _pcm.waitUntilDone();
  }

  Future<VoicePrivateWav> _writeTempWav(List<int> bytes) {
    return VoicePrivateWav.write(bytes);
  }

  Future<void> _playFileAndWait(VoicePrivateWav wav, int token) async {
    Future<void> deleteTemp() => wav.delete();

    if (token != _playbackToken) {
      await deleteTemp();
      return;
    }
    final StartedProcess started;
    try {
      started = await _startPlayer(wav.path);
    } on Object {
      await deleteTemp();
      rethrow;
    }
    if (token != _playbackToken) {
      started.kill();
      try {
        await started.exitCode;
      } finally {
        await deleteTemp();
      }
      return;
    }
    _player = started;
    final player = started;
    try {
      final exitCode = await player.exitCode;
      if (exitCode != 0 && token == _playbackToken) {
        throw StateError('Voice playback failed with exit code $exitCode.');
      }
    } finally {
      if (identical(_player, player)) {
        _player = null;
      }
      await deleteTemp();
    }
  }

  Future<void> stopPlayback() async {
    _playbackToken += 1;
    final player = _player;
    _player = null;
    _streaming = false;
    player?.kill();
    await _pcm.stop();
  }

  Future<void> dispose() async {
    try {
      await stopCapture();
    } on Object {
      // Capture stop must not skip playback stop.
    }
    try {
      await stopPlayback();
    } on Object {
      // Playback stop must not skip recorder dispose.
    }
    try {
      await _recorder?.dispose();
    } on Object {
      // Recorder dispose must not skip frame-controller close.
    }
    _recorder = null;
    try {
      await _frames.close();
    } on Object {
      // Best-effort frame-controller close on audio dispose.
    }
  }

  Future<StartedProcess> _startPlayer(String path) {
    if (Platform.isMacOS) {
      return _runner.start('afplay', <String>[path]);
    }
    if (Platform.isWindows) {
      final escaped = path.replaceAll("'", "''");
      return _runner.start('powershell', <String>[
        '-NoProfile',
        '-Command',
        "(New-Object Media.SoundPlayer '$escaped').PlaySync()",
      ]);
    }
    return _runner.start('aplay', <String>['-q', path]);
  }

  void _onBytes(Uint8List chunk) {
    const bytesPerFrame = 640; // 20 ms of 16 kHz mono PCM16
    if (chunk.isEmpty) {
      return;
    }
    _pcmRemainder.add(chunk);
    var buffer = _pcmRemainder.takeBytes();
    var offset = 0;
    while (buffer.length - offset >= bytesPerFrame) {
      final frameBytes = Uint8List.sublistView(
        buffer,
        offset,
        offset + bytesPerFrame,
      );
      offset += bytesPerFrame;
      final samples = Int16List(bytesPerFrame ~/ 2);
      final view = ByteData.sublistView(frameBytes);
      var sumSquares = 0.0;
      for (var i = 0; i < samples.length; i++) {
        final sample = view.getInt16(i * 2, Endian.little);
        samples[i] = sample;
        final normalized = sample / 32768.0;
        sumSquares += normalized * normalized;
      }
      _frames.add(
        VoicePcmFrame(
          samples: samples,
          rms: math.sqrt(sumSquares / samples.length),
        ),
      );
    }
    if (offset < buffer.length) {
      _pcmRemainder.add(Uint8List.sublistView(buffer, offset));
    }
  }
}

Uint8List pcm16ToWav(List<int> pcm, {int sampleRate = 16000}) {
  final data = Uint8List.fromList(pcm);
  final header = ByteData(44);
  final byteRate = sampleRate * 2;
  header.setUint32(0, 0x46464952, Endian.little); // RIFF
  header.setUint32(4, 36 + data.length, Endian.little);
  header.setUint32(8, 0x45564157, Endian.little); // WAVE
  header.setUint32(12, 0x20746d66, Endian.little); // fmt
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  header.setUint32(36, 0x61746164, Endian.little); // data
  header.setUint32(40, data.length, Endian.little);
  return Uint8List.fromList(<int>[...header.buffer.asUint8List(), ...data]);
}

bool looksLikeHomeCancel(String text) {
  return const <String>{
    'para',
    'stop',
    'cancel',
    'cancela',
    'cancelar',
    'cállate',
    'callate',
    'silencio',
    'basta',
  }.contains(_normalizeHomeCancel(text));
}

String _normalizeHomeCancel(String text) {
  var normalized = text.trim();
  while (true) {
    final next = normalized
        .replaceAll(RegExp(r'''^[¡!¿?.,;:…"''“”()\[\]{}]+'''), '')
        .replaceAll(RegExp(r'''[¡!¿?.,;:…"''“”()\[\]{}]+$'''), '')
        .trim();
    if (next == normalized) {
      break;
    }
    normalized = next;
  }
  return normalized.toLowerCase();
}
