part of 'voice_session_controller.dart';

/// VAD framing, the realtime send queue, and chained STT turns.
mixin _VoiceSessionCapture
    on _$VoiceSessionController, _VoiceSessionFields, _VoiceSessionPlayback {
  void _onFrame(VoicePcmFrame frame) {
    if (!_listening) {
      return;
    }
    final event = _vad.observe(frame.rms, speaking: _playing);
    switch (event) {
      case VoiceActivityEvent.speechStart:
        _playbackGeneration += 1;
        _invalidatePlayback();
        unawaited(_audio?.stopPlayback());
        _playing = false;
        _streamingPlayback = false;
        _realtimePlayback.clear();
        if (!_realtime) {
          unawaited(_client.sendActivity('start'));
        }
        _utterance.clear();
        for (final preroll in _vadPreroll) {
          _appendPcm(preroll);
        }
        _vadPreroll.clear();
        _appendPcm(frame.samples);
        if (_realtime) {
          final pcm = _utterance.takeBytes();
          _utterance.add(pcm);
          _queueRealtimeStart(pcm);
        }
      case VoiceActivityEvent.none:
        if (_vad.capturing) {
          _appendPcm(frame.samples);
          if (_realtime) {
            _queueRealtimeAudio(_pcmBytes(frame.samples));
          }
        } else {
          _vadPreroll.add(Int16List.fromList(frame.samples));
          if (_vadPreroll.length > 4) {
            _vadPreroll.removeAt(0);
          }
        }
      case VoiceActivityEvent.speechEnd:
        _appendPcm(frame.samples);
        final pcm = _utterance.takeBytes();
        if (_realtime) {
          _queueRealtimeEnd(_pcmBytes(frame.samples));
        } else {
          _enqueueTurn(pcm);
        }
    }
  }

  List<int> _pcmBytes(Int16List samples) {
    return Uint8List.view(
      samples.buffer,
      samples.offsetInBytes,
      samples.lengthInBytes,
    );
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
              for (final op in batch) {
                if (epoch != _captureEpoch) {
                  return;
                }
                switch (op) {
                  case _VoiceRealtimeStart():
                    await _client.sendActivity('start');
                  case _VoiceRealtimeAudio(:final pcm):
                    if (pcm.isNotEmpty) {
                      await _client.sendAudio(pcm);
                    }
                  case _VoiceRealtimeEnd():
                    await _client.sendActivity('end');
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

  void _enqueueTurn(List<int> pcm) {
    final epoch = _captureEpoch;
    _turnChain = _turnChain
        .then((_) async {
          if (epoch != _captureEpoch) {
            return;
          }
          await _submitUtterance(pcm, epoch: epoch);
        })
        .catchError((Object _) {});
  }

  void _appendPcm(Int16List samples) {
    _utterance.add(
      Uint8List.view(
        samples.buffer,
        samples.offsetInBytes,
        samples.lengthInBytes,
      ),
    );
  }

  Future<void> _submitUtterance(List<int> pcm, {required int epoch}) async {
    if (pcm.isEmpty || epoch != _captureEpoch) {
      return;
    }
    try {
      if (_settings.sttProvider == VoiceSttProvider.geminiTranscribeLive) {
        await _client.submitTurn('', pcm16k: pcm);
        if (epoch != _captureEpoch) {
          return;
        }
        await refresh();
        return;
      }
      final text = await _transcribe(pcm, epoch: epoch);
      if (epoch != _captureEpoch) {
        return;
      }
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        return;
      }
      await _client.submitTurn(
        trimmed,
        cancelHome: looksLikeHomeCancel(trimmed),
      );
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

  Future<String> _transcribe(List<int> pcm, {required int epoch}) async {
    final wav = pcm16ToWav(pcm);
    final private = await VoicePrivateWav.write(
      wav,
      prefix: 'alera-voice-turn',
    );
    final requestId = 'voice-${const Uuid().v4()}';
    _activeDictationIds.add(requestId);
    try {
      if (epoch != _captureEpoch) {
        return '';
      }
      final settings = _settings;
      final dictation = ref.read(settingsControllerProvider).aiDictation;
      final request = AiDictationRequest(
        requestId: requestId,
        audioPath: private.path,
        modelPath: settings.sttProvider == VoiceSttProvider.localWhisper
            ? await ref
                  .read(aiDictationModelStoreProvider)
                  .modelPath(dictation.localModelId)
            : null,
        language: dictation.language,
        remoteEngine: switch (settings.sttProvider) {
          VoiceSttProvider.codexRealtime =>
            AiDictationRemoteEngine.codexSubscription,
          VoiceSttProvider.openAiCompatible =>
            AiDictationRemoteEngine.openAiCompatible,
          VoiceSttProvider.geminiTranscribeLive ||
          VoiceSttProvider.localWhisper => null,
        },
        providerBaseUrl: dictation.remoteBaseUrl,
        providerModel: dictation.remoteModel,
        timeout: const Duration(seconds: 60),
      );
      if (epoch != _captureEpoch) {
        return '';
      }
      final result = settings.sttProvider == VoiceSttProvider.localWhisper
          ? await (_nativeDictation ??= NativeAiDictationProvider()).transcribe(
              request,
            )
          : await (_runtimeDictation ??= RuntimeAiDictationProvider(
              ref.read(runtimeHostClientProvider),
            )).transcribe(request);
      if (epoch != _captureEpoch) {
        return '';
      }
      return result.text;
    } finally {
      _activeDictationIds.remove(requestId);
      await private.delete();
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
