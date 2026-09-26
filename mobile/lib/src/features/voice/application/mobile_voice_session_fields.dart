part of 'mobile_voice_session_controller.dart';

/// Session state shared by the lifecycle, capture, and playback mixins.
mixin _MobileVoiceSessionFields on _$MobileVoiceSessionController {
  StreamSubscription<MobileRuntimeEvent>? _events;
  final MobileVoiceCapture _capture = MobileVoiceCapture();
  AudioPlayer? _player;
  final VoicePcmPlayer _pcm = VoicePcmPlayer();
  final VoiceActivityDetector _vad = VoiceActivityDetector();
  final BytesBuilder _utterance = BytesBuilder(copy: false);
  var _listening = false;
  var _playbackEnabled = false;
  final List<Int16List> _vadPreroll = <Int16List>[];
  final BytesBuilder _pcmRemainder = BytesBuilder(copy: false);
  var _starting = false;
  var _playing = false;
  var _realtime = false;
  var _streamingPlayback = false;
  final BytesBuilder _realtimePlayback = BytesBuilder(copy: false);
  var _realtimeSampleRate = 24000;
  Future<void> _realtimeSends = Future<void>.value();
  Future<void> _playbackSends = Future<void>.value();
  Future<void> _speakChain = Future<void>.value();
  Future<void> _teardown = Future<void>.value();
  Future<void> _sessionShutdown = Future<void>.value();
  var _realtimeFlushing = false;
  var _playbackGeneration = 0;
  var _captureEpoch = 0;
  var _stopToken = 0;
  int? _activePlaybackId;
  var _rejectUnidentifiedPlayback = false;
  final Set<int> _invalidPlaybackIds = <int>{};
  final Set<int> _admittedPlaybackIds = <int>{};
  MobileRuntimeClient? _retainedClient;
  var _bindGeneration = 0;
  final List<_VoiceRealtimeOp> _pendingRealtime = <_VoiceRealtimeOp>[];

  Future<void> refresh();

  Future<MobileRuntimeClient> _liveClient() {
    return ref.read(hostConnectionControllerProvider(hostId).future);
  }

  Future<MobileRuntimeClient> _client() async {
    return _retainedClient ?? await _liveClient();
  }

  MobileVoiceSessionState _fromStatus(
    Map<String, Object?> status, {
    required bool supported,
    required bool active,
    bool busy = false,
  }) {
    return MobileVoiceSessionState(
      supported: supported,
      active: active,
      busy: busy,
      phase: status['phase'] as String? ?? 'idle',
      realtime: status['realtime'] == true,
      queuedSpeakCount: _asInt(status['queuedSpeakCount']),
      queuedTurnCount: _asInt(status['queuedTurnCount']),
      lastSpoken: status['lastSpoken'] as String?,
      lastError: status['lastError'] as String?,
    );
  }

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}
