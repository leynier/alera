import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

/// Live PCM16 playback for realtime voice. SoLoud covers Windows, Linux,
/// macOS, Android, and iOS. `just_audio` cannot feed raw PCM as it arrives.
class VoicePcmPlayer {
  AudioSource? _source;
  SoundHandle? _handle;
  var _sampleRate = 24000;
  var _accepting = false;
  var _epoch = 0;
  Future<void> _lifecycle = Future<void>.value();

  bool get isStreaming => _accepting;

  Future<void> start({required int sampleRate}) {
    if (_accepting && _sampleRate == sampleRate) {
      return Future<void>.value();
    }
    final epoch = ++_epoch;
    final started = _lifecycle.then((_) async {
      if (epoch != _epoch) {
        return;
      }
      await _disposeCurrent();
      if (epoch != _epoch) {
        return;
      }
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) {
        await soloud.init();
      }
      if (epoch != _epoch) {
        return;
      }
      _sampleRate = sampleRate;
      AudioSource? source;
      try {
        source = soloud.setBufferStream(
          bufferingType: BufferingType.released,
          sampleRate: sampleRate,
          channels: Channels.mono,
          format: BufferType.s16le,
          bufferingTimeNeeds: 0.12,
        );
        final handle = soloud.play(source);
        if (epoch != _epoch) {
          await _disposeNative(handle, source);
          return;
        }
        _source = source;
        _handle = handle;
        _accepting = true;
      } on Object {
        await _disposeNative(null, source);
        rethrow;
      }
    });
    _lifecycle = started.catchError((Object _) {});
    return started;
  }

  void write(List<int> pcm) {
    final source = _source;
    if (!_accepting || source == null || pcm.isEmpty) {
      return;
    }
    SoLoud.instance.addAudioDataStream(source, Uint8List.fromList(pcm));
  }

  void finish() {
    final source = _source;
    if (source == null) {
      return;
    }
    SoLoud.instance.setDataIsEnded(source);
    _accepting = false;
  }

  Future<void> waitUntilDone() async {
    final handle = _handle;
    if (handle == null) {
      return;
    }
    final soloud = SoLoud.instance;
    while (soloud.isInitialized && soloud.getIsValidVoiceHandle(handle)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> stop() {
    _epoch += 1;
    _accepting = false;
    final handle = _handle;
    final source = _source;
    _handle = null;
    _source = null;
    final stopped = _lifecycle.then((_) => _disposeNative(handle, source));
    _lifecycle = stopped.catchError((Object _) {});
    return stopped;
  }

  Future<void> _disposeCurrent() {
    final handle = _handle;
    final source = _source;
    _handle = null;
    _source = null;
    _accepting = false;
    return _disposeNative(handle, source);
  }

  Future<void> _disposeNative(SoundHandle? handle, AudioSource? source) async {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      return;
    }
    Object? firstError;
    StackTrace? firstStack;
    if (handle != null) {
      try {
        await soloud.stop(handle);
      } on Object catch (error, stack) {
        firstError = error;
        firstStack = stack;
      }
    }
    if (source != null) {
      try {
        await soloud.disposeSource(source);
      } on Object catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }
}
