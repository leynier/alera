// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'mobile_ai_dictation_controller.dart';

extension MobileAiDictationLifecycle on MobileAiDictationController {
  void _handleAppPaused() {
    if (ref.mounted && state.stage == MobileAiDictationStage.recording) {
      unawaited(cancel());
    }
  }

  bool _isCurrentGeneration(int generation) =>
      ref.mounted && _operation.isCurrent(generation);

  bool _canContinue([int? generation]) =>
      ref.mounted &&
      !_operation.cancelRequested &&
      (generation == null || _operation.isCurrent(generation));

  void _trackActiveRequest(String id, Future<void> Function() cancel) {
    _activeRequest = (id: id, cancel: cancel);
  }

  void _clearActiveRequest(String id) {
    if (_activeRequest?.id == id) _activeRequest = null;
  }

  Future<void> _cancelActiveRequest(
    ({String id, Future<void> Function() cancel}) request,
  ) async {
    _clearActiveRequest(request.id);
    try {
      await request.cancel();
    } on Object {
      // Local cleanup must still complete when the paired device disconnects.
    }
  }

  Future<void> _dispose(
    Future<void>? activeTranscription,
    ({String id, Future<void> Function() cancel})? activeRequest,
  ) async {
    if (activeRequest != null) {
      await _cancelActiveRequest(activeRequest);
    }
    final segmentRotation = _segmentRotation;
    if (segmentRotation != null) {
      try {
        await segmentRotation;
      } on Object catch (error, stackTrace) {
        _log.warning('dictation segment cleanup failed', error, stackTrace);
      }
    }
    if (activeTranscription != null) {
      try {
        await activeTranscription;
      } on Object {
        // Disposal must release native resources even when transcription fails.
      }
    }
    await _deleteRecording();
  }
}
