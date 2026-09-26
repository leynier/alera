part of 'voice_session_controller.dart';

/// Session state shared by the lifecycle, capture, and playback mixins.
mixin _VoiceSessionFields on _$VoiceSessionController {
  StreamSubscription<RuntimeHostEvent>? _events;
  StreamSubscription<VoicePcmFrame>? _frames;
  VoiceAudioIo? _audio;
  final VoiceActivityDetector _vad = VoiceActivityDetector();
  final BytesBuilder _utterance = BytesBuilder(copy: false);
  var _listening = false;
  var _starting = false;
  var _playbackEnabled = false;
  final List<Int16List> _vadPreroll = <Int16List>[];
  var _playing = false;
  var _realtime = false;
  var _streamingPlayback = false;
  final BytesBuilder _realtimePlayback = BytesBuilder(copy: false);
  var _realtimeSampleRate = 24000;
  Future<void> _realtimeSends = Future<void>.value();
  Future<void> _playbackSends = Future<void>.value();
  Future<void> _speakChain = Future<void>.value();
  Future<void> _turnChain = Future<void>.value();
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
  final Set<String> _activeDictationIds = <String>{};
  NativeAiDictationProvider? _nativeDictation;
  RuntimeAiDictationProvider? _runtimeDictation;
  final List<_VoiceRealtimeOp> _pendingRealtime = <_VoiceRealtimeOp>[];

  RuntimeVoiceClient get _client => ref.read(runtimeVoiceClientProvider);

  VoiceSettings get _settings => ref.read(settingsControllerProvider).voice;

  Future<void> refresh();
}
