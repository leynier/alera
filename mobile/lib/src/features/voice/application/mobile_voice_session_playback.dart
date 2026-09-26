part of 'mobile_voice_session_controller.dart';

/// Playback identity (barge-in invalidation) plus chained and realtime audio
/// output.
mixin _MobileVoiceSessionPlayback
    on _$MobileVoiceSessionController, _MobileVoiceSessionFields {
  void _enqueuePlayback(
    Future<void> Function(
      Map<String, Object?> payload,
      int generation,
      int epoch,
    )
    work,
    Map<String, Object?> payload,
  ) {
    final epoch = _captureEpoch;
    final generation = _playbackGeneration;
    final utteranceId = _payloadUtteranceId(payload);
    _playbackSends = _playbackSends
        .then((_) async {
          if (epoch != _captureEpoch ||
              generation != _playbackGeneration ||
              !_acceptsPlaybackId(utteranceId)) {
            return;
          }
          await work(payload, generation, epoch);
        })
        .catchError((Object _) {});
  }

  int? _payloadUtteranceId(Map<String, Object?> payload) {
    final id = payload['id'];
    return id is num ? id.toInt() : null;
  }

  void _invalidatePlayback({int? id}) {
    if (id != null) {
      _invalidPlaybackIds.add(id);
      _admittedPlaybackIds.remove(id);
      if (_activePlaybackId == id) {
        _activePlaybackId = null;
      }
      return;
    }
    _invalidPlaybackIds.addAll(_admittedPlaybackIds);
    final active = _activePlaybackId;
    if (active != null) {
      _invalidPlaybackIds.add(active);
    }
    _admittedPlaybackIds.clear();
    _activePlaybackId = null;
    _rejectUnidentifiedPlayback = true;
  }

  void _retirePlaybackId(int? id) {
    if (id != null && _activePlaybackId == id) {
      _activePlaybackId = null;
    }
    if (id != null) {
      _admittedPlaybackIds.remove(id);
    }
  }

  bool _acceptsPlaybackId(int? id) {
    if (!_playbackEnabled) {
      return false;
    }
    if (id == null) {
      return !_rejectUnidentifiedPlayback &&
          _activePlaybackId == null &&
          _invalidPlaybackIds.isEmpty;
    }
    if (_invalidPlaybackIds.contains(id)) {
      return false;
    }
    if (_rejectUnidentifiedPlayback) {
      return _admittedPlaybackIds.contains(id) || _activePlaybackId == id;
    }
    final active = _activePlaybackId;
    return active == null || active == id;
  }

  void _enqueueSpeak(String text, {int? id}) {
    final epoch = _captureEpoch;
    final generation = _playbackGeneration;
    _speakChain = _speakChain
        .then((_) async {
          if (epoch != _captureEpoch ||
              generation != _playbackGeneration ||
              !_playbackEnabled) {
            return;
          }
          await _speakChained(
            text,
            id: id,
            generation: generation,
            epoch: epoch,
          );
        })
        .catchError((Object _) {});
  }

  Future<void> _speakChained(
    String text, {
    int? id,
    required int generation,
    required int epoch,
  }) async {
    try {
      final client = await _client();
      final audio = await client.synthesizeVoice(text);
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      if (audio.isEmpty) {
        throw StateError('Voice synthesis returned no audio.');
      }
      _playing = true;
      final player = _player ??= AudioPlayer();
      await player.setUrl(
        Uri.dataFromBytes(audio, mimeType: 'audio/wav').toString(),
      );
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        await player.stop();
        return;
      }
      await player.play();
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      await client.markVoiceSpoken(text, id: id);
      _playing = false;
      await refresh();
    } on Object catch (error) {
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      _playing = false;
      try {
        final client = await _client();
        if (generation != _playbackGeneration || epoch != _captureEpoch) {
          return;
        }
        await client.markVoiceSpoken(
          text,
          id: id,
          failed: true,
          error: error.toString(),
        );
        await refresh();
      } on Object {
        state = state.copyWith(lastError: error.toString());
      }
    }
  }

  Future<void> _onRealtimeAudio(
    Map<String, Object?> payload,
    int generation,
    int epoch,
  ) async {
    final utteranceId = _payloadUtteranceId(payload);
    if (!_acceptsPlaybackId(utteranceId)) {
      return;
    }
    if (utteranceId != null) {
      _activePlaybackId = utteranceId;
    }
    final encoded = payload['audioBase64'];
    if (encoded is! String || encoded.isEmpty) {
      return;
    }
    final pcm = base64Decode(encoded);
    final sampleRate = payload['sampleRate'];
    if (sampleRate is num) {
      _realtimeSampleRate = sampleRate.toInt();
    }
    _playing = true;
    if (!_streamingPlayback) {
      try {
        await _pcm.start(sampleRate: _realtimeSampleRate);
        if (generation != _playbackGeneration || epoch != _captureEpoch) {
          await _pcm.stop();
          return;
        }
        _streamingPlayback = _pcm.isStreaming;
      } on Object catch (error) {
        await _failRealtimePlayback(
          utteranceId: utteranceId,
          text: null,
          error: error,
          generation: generation,
          epoch: epoch,
        );
        return;
      }
    }
    if (generation != _playbackGeneration || epoch != _captureEpoch) {
      return;
    }
    if (_streamingPlayback) {
      try {
        _pcm.write(pcm);
      } on Object catch (error) {
        await _failRealtimePlayback(
          utteranceId: utteranceId,
          text: null,
          error: error,
          generation: generation,
          epoch: epoch,
        );
      }
      return;
    }
    _realtimePlayback.add(pcm);
  }

  Future<void> _flushRealtimePlayback(
    Map<String, Object?> payload,
    int generation,
    int epoch,
  ) async {
    final utteranceId = _payloadUtteranceId(payload);
    if (!_acceptsPlaybackId(utteranceId)) {
      return;
    }
    final spoken = payload['text'];
    final text = spoken is String ? spoken : null;
    final id = payload['id'];
    if (_streamingPlayback) {
      try {
        _pcm.finish();
        await _pcm.waitUntilDone();
      } on Object catch (error) {
        await _failRealtimePlayback(
          utteranceId: utteranceId,
          text: text,
          error: error,
          generation: generation,
          epoch: epoch,
        );
        return;
      }
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      _streamingPlayback = false;
      _playing = false;
      _retirePlaybackId(utteranceId);
      await _ackSpoken(text, id: id is num ? id.toInt() : null);
      return;
    }
    final pcm = _realtimePlayback.takeBytes();
    if (pcm.isEmpty) {
      await _failRealtimePlayback(
        utteranceId: utteranceId,
        text: text,
        error: StateError('Realtime playback received no audio.'),
        generation: generation,
        epoch: epoch,
      );
      return;
    }
    try {
      final wav = pcm16ToWav(pcm, sampleRate: _realtimeSampleRate);
      final player = _player ??= AudioPlayer();
      _playing = true;
      await player.setUrl(
        Uri.dataFromBytes(wav, mimeType: 'audio/wav').toString(),
      );
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        await player.stop();
        return;
      }
      await player.play();
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      _playing = false;
      _retirePlaybackId(utteranceId);
      await _ackSpoken(text, id: id is num ? id.toInt() : null);
    } on Object catch (error) {
      await _failRealtimePlayback(
        utteranceId: utteranceId,
        text: text,
        error: error,
        generation: generation,
        epoch: epoch,
      );
    }
  }

  Future<void> _ackSpoken(
    String? text, {
    int? id,
    bool failed = false,
    String? error,
  }) async {
    final spoken = text?.trim() ?? '';
    if (spoken.isEmpty && !failed) {
      return;
    }
    final client = await _client();
    await client.markVoiceSpoken(spoken, id: id, failed: failed, error: error);
    await refresh();
  }

  Future<void> _failRealtimePlayback({
    required int? utteranceId,
    required String? text,
    required Object error,
    required int generation,
    required int epoch,
  }) async {
    if (generation != _playbackGeneration || epoch != _captureEpoch) {
      return;
    }
    _playing = false;
    _streamingPlayback = false;
    _realtimePlayback.clear();
    _retirePlaybackId(utteranceId);
    _invalidatePlayback(id: utteranceId);
    try {
      await _stopPlayback();
    } on Object {
      // Native stop must not skip retiring the failed host utterance.
    }
    if (generation != _playbackGeneration || epoch != _captureEpoch) {
      return;
    }
    try {
      await _ackSpoken(
        text,
        id: utteranceId,
        failed: true,
        error: error.toString(),
      );
    } on Object {
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      state = state.copyWith(lastError: error.toString());
    }
  }

  Future<void> _stopPlayback() async {
    _streamingPlayback = false;
    _realtimePlayback.clear();
    final pcmStop = _pcm.stop();
    try {
      await _player?.stop();
    } on Object {
      // WAV stop must not skip PCM stop.
    }
    try {
      await pcmStop;
    } on Object {
      // PCM stop must not skip remaining shutdown.
    }
  }
}
