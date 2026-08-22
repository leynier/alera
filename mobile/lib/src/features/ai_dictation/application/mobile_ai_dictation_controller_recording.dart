// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'mobile_ai_dictation_controller.dart';

extension MobileAiDictationRecording on MobileAiDictationController {
  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _player = player;
    _subscriptions.add(
      player.positionStream.listen((position) {
        if (ref.mounted &&
            (state.stage == MobileAiDictationStage.playing ||
                state.hasRecording)) {
          state = state.copyWith(playbackPosition: position);
        }
      }),
    );
    _subscriptions.add(
      player.playerStateStream.listen((playerState) {
        if (ref.mounted &&
            playerState.processingState == ProcessingState.completed &&
            state.stage == MobileAiDictationStage.playing) {
          unawaited(player.seek(Duration.zero));
          state = state.copyWith(
            stage: MobileAiDictationStage.recorded,
            playbackPosition: Duration.zero,
          );
        }
      }),
    );
    return player;
  }

  Future<void> _rotateRecordingSegment(int generation) async {
    if (!_isCurrentGeneration(generation) ||
        state.stage != MobileAiDictationStage.recording ||
        _audioPath == null) {
      return;
    }
    final completedPath = await _recorder?.stop();
    if (!_isCurrentGeneration(generation)) return;
    if (completedPath != null && completedPath != _audioPath) {
      final index = _audioPaths.indexOf(_audioPath!);
      if (index >= 0) _audioPaths[index] = completedPath;
      _audioPath = completedPath;
    }
    if (!_isCurrentGeneration(generation) ||
        state.stage != MobileAiDictationStage.recording) {
      return;
    }
    final directory = await getTemporaryDirectory();
    if (!_isCurrentGeneration(generation)) return;
    final path = p.join(
      directory.path,
      'alera-mobile-dictation-${DateTime.now().microsecondsSinceEpoch}-${_audioPaths.length}.wav',
    );
    await _recorder?.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    if (!_isCurrentGeneration(generation)) return;
    _audioPath = path;
    _audioPaths.add(path);
    state = state.copyWith(segmentCount: _audioPaths.length);
  }

  Future<void> _deleteRecording() async {
    final paths = _audioPaths.toSet().toList();
    _audioPaths.clear();
    _audioPath = null;
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }
}
