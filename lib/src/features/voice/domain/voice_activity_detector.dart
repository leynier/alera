/// Energy-based endpointer for always-on listening and barge-in.
///
/// Speech starts after [startFrames] loud frames. A turn ends after
/// [endSilenceFrames] quiet frames. Playback barge-in uses a higher
/// [bargeInRms] so speaker echo is less likely to cut TTS.
class VoiceActivityDetector({
  this.startRms = 0.04,
  this.bargeInRms = 0.08,
  this.startFrames = 4,
  this.endSilenceFrames = 18,
}) {
  final double startRms;
  final double bargeInRms;
  final int startFrames;
  final int endSilenceFrames;
  var _loudFrames = 0;
  var _quietFrames = 0;
  var capturing = false;

  void reset() {
    _loudFrames = 0;
    _quietFrames = 0;
    capturing = false;
  }

  VoiceActivityEvent observe(double rms, {required bool speaking}) {
    final startThreshold = speaking ? bargeInRms : startRms;
    if (rms >= startThreshold) {
      _loudFrames += 1;
      _quietFrames = 0;
      if (!capturing && _loudFrames >= startFrames) {
        capturing = true;
        return VoiceActivityEvent.speechStart;
      }
      return VoiceActivityEvent.none;
    }
    _loudFrames = 0;
    if (!capturing) {
      return VoiceActivityEvent.none;
    }
    _quietFrames += 1;
    if (_quietFrames >= endSilenceFrames) {
      capturing = false;
      _quietFrames = 0;
      return VoiceActivityEvent.speechEnd;
    }
    return VoiceActivityEvent.none;
  }
}

enum VoiceActivityEvent { none, speechStart, speechEnd }
