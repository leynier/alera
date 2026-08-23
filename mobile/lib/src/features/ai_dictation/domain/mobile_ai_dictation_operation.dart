final class MobileAiDictationOperation {
  var _generation = 0;
  int? _activeGeneration;
  var _cancelRequested = false;
  var _disposed = false;

  int? get activeGeneration => _activeGeneration;
  bool get cancelRequested => _cancelRequested;

  int begin() {
    final generation = ++_generation;
    _activeGeneration = generation;
    _cancelRequested = false;
    return generation;
  }

  bool isCurrent(int generation) =>
      !_disposed && !_cancelRequested && _activeGeneration == generation;

  void cancel() {
    _cancelRequested = true;
    _activeGeneration = null;
    _generation++;
  }

  void complete() {
    _activeGeneration = null;
    _generation++;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
