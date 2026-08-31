class CodexSubmissionAttempts {
  final Map<String, List<String>> _failed = {};

  String claim(String signature, String newId) {
    final attempts = _failed[signature];
    if (attempts == null || attempts.isEmpty) return newId;
    final id = attempts.removeAt(0);
    if (attempts.isEmpty) _failed.remove(signature);
    return id;
  }

  void retainForRetry(String signature, String id) {
    final attempts = _failed.putIfAbsent(signature, () => []);
    if (!attempts.contains(id)) attempts.add(id);
  }
}
