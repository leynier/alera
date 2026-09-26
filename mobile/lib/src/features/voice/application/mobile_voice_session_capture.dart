part of 'mobile_voice_session_controller.dart';

/// Microphone capture, VAD framing, and the realtime/chained send queues.
mixin _MobileVoiceSessionCapture
    on
        _$MobileVoiceSessionController,
        _MobileVoiceSessionFields,
        _MobileVoiceSessionPlayback {
  Future<void> _startCapture(int epoch) {
    return _capture.start(_onBytes, stillValid: () => epoch == _captureEpoch);
  }

  Future<void> _stopOwnedCapture(int epoch) async {
    if (epoch != _captureEpoch) {
      return;
    }
    _listening = false;
    _starting = false;
    _playbackEnabled = false;
    _captureEpoch += 1;
    final owned = _captureEpoch;
    _playbackGeneration += 1;
    _invalidatePlayback();
    _pendingRealtime.clear();
    _realtimeFlushing = false;
    _pcmRemainder.clear();
    final teardown = () async {
      try {
        await _capture.stop();
      } on Object {
        // Recorder stop must not skip playback stop.
      }
      try {
        await _stopPlayback();
      } on Object {
        // Playback stop must not skip remaining shutdown.
      }
      if (owned != _captureEpoch) {
        return;
      }
      _playing = false;
    }();
    _teardown = _teardown.then((_) => teardown).catchError((Object _) {});
    await _teardown;
  }

  void _onBytes(Uint8List chunk) {
    if (!_listening || chunk.isEmpty) {
      return;
    }
    const bytesPerFrame = 640;
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
      _onFixedFrame(pcmFrameFromBytes(frameBytes));
    }
    if (offset < buffer.length) {
      _pcmRemainder.add(Uint8List.sublistView(buffer, offset));
    }
  }

  void _onFixedFrame(MobileVoicePcmFrame frame) {
    final event = _vad.observe(frame.rms, speaking: _playing);
    switch (event) {
      case VoiceActivityEvent.speechStart:
        _playbackGeneration += 1;
        _invalidatePlayback();
        unawaited(_stopPlayback());
        _playing = false;
        _streamingPlayback = false;
        _realtimePlayback.clear();
        if (!_realtime) {
          _enqueueChainedBargeIn();
        }
        _utterance.clear();
        for (final preroll in _vadPreroll) {
          _append(preroll);
        }
        _vadPreroll.clear();
        _append(frame.samples);
        if (_realtime) {
          final pcm = _utterance.takeBytes();
          _utterance.add(pcm);
          _queueRealtimeStart(pcm);
        }
      case VoiceActivityEvent.none:
        if (_vad.capturing) {
          _append(frame.samples);
          if (_realtime) {
            _queueRealtimeAudio(pcmBytes(frame.samples));
          }
        } else {
          _vadPreroll.add(Int16List.fromList(frame.samples));
          if (_vadPreroll.length > 4) {
            _vadPreroll.removeAt(0);
          }
        }
      case VoiceActivityEvent.speechEnd:
        _append(frame.samples);
        final pcm = _utterance.takeBytes();
        if (_realtime) {
          _queueRealtimeEnd(pcmBytes(frame.samples));
        } else {
          unawaited(_submitUtterance(pcm, epoch: _captureEpoch));
        }
    }
  }

  void _append(Int16List samples) {
    _utterance.add(pcmBytes(samples));
  }

  void _enqueueChainedBargeIn() {
    final epoch = _captureEpoch;
    _realtimeSends = _realtimeSends
        .then((_) async {
          if (epoch != _captureEpoch) {
            return;
          }
          final client = await _client();
          if (epoch != _captureEpoch) {
            return;
          }
          await client.sendVoiceActivity('start');
        })
        .catchError((Object _) {});
  }

  void _queueRealtimeStart(List<int> pcm) {
    _pendingRealtime.add(const _VoiceRealtimeOp.start());
    if (pcm.isNotEmpty) {
      _pendingRealtime.add(_VoiceRealtimeOp.audio(pcm));
    }
    _scheduleRealtimeFlush();
  }

  void _queueRealtimeAudio(List<int> pcm) {
    if (pcm.isEmpty) {
      return;
    }
    final last = _pendingRealtime.isEmpty ? null : _pendingRealtime.last;
    if (last is _VoiceRealtimeAudio) {
      last.pcm.addAll(pcm);
    } else {
      _pendingRealtime.add(_VoiceRealtimeOp.audio(pcm));
    }
    _scheduleRealtimeFlush();
  }

  void _queueRealtimeEnd(List<int> pcm) {
    if (pcm.isNotEmpty) {
      _queueRealtimeAudio(pcm);
    }
    _pendingRealtime.add(const _VoiceRealtimeOp.end());
    _scheduleRealtimeFlush();
  }

  void _scheduleRealtimeFlush() {
    if (_realtimeFlushing) {
      return;
    }
    _realtimeFlushing = true;
    final epoch = _captureEpoch;
    _realtimeSends = _realtimeSends
        .then((_) async {
          try {
            while (epoch == _captureEpoch) {
              if (_pendingRealtime.isEmpty) {
                break;
              }
              final batch = List<_VoiceRealtimeOp>.of(_pendingRealtime);
              _pendingRealtime.clear();
              final client = await _client();
              if (epoch != _captureEpoch) {
                return;
              }
              for (final op in batch) {
                if (epoch != _captureEpoch) {
                  return;
                }
                switch (op) {
                  case _VoiceRealtimeStart():
                    await client.sendVoiceActivity('start');
                  case _VoiceRealtimeAudio(:final pcm):
                    if (pcm.isNotEmpty) {
                      await client.sendVoiceAudio(pcm);
                    }
                  case _VoiceRealtimeEnd():
                    await client.sendVoiceActivity('end');
                }
              }
            }
          } finally {
            if (epoch == _captureEpoch) {
              _realtimeFlushing = false;
              if (_pendingRealtime.isNotEmpty) {
                _scheduleRealtimeFlush();
              }
            }
          }
        })
        .catchError((Object _) {});
  }

  Future<void> _submitUtterance(List<int> pcm, {required int epoch}) async {
    if (pcm.isEmpty || epoch != _captureEpoch) {
      return;
    }
    try {
      final client = await _client();
      await client.submitVoiceTurn('', pcm16k: pcm);
      if (epoch != _captureEpoch) {
        return;
      }
      await refresh();
    } on Object catch (error) {
      if (epoch != _captureEpoch) {
        return;
      }
      state = state.copyWith(lastError: error.toString());
    }
  }
}

sealed class _VoiceRealtimeOp {
  const _VoiceRealtimeOp();

  const factory _VoiceRealtimeOp.start() = _VoiceRealtimeStart;

  const factory _VoiceRealtimeOp.end() = _VoiceRealtimeEnd;

  factory _VoiceRealtimeOp.audio(List<int> pcm) = _VoiceRealtimeAudio;
}

final class _VoiceRealtimeStart extends _VoiceRealtimeOp {
  const _VoiceRealtimeStart();
}

final class _VoiceRealtimeEnd extends _VoiceRealtimeOp {
  const _VoiceRealtimeEnd();
}

final class _VoiceRealtimeAudio extends _VoiceRealtimeOp {
  _VoiceRealtimeAudio(List<int> pcm) : pcm = List<int>.of(pcm);

  final List<int> pcm;
}
