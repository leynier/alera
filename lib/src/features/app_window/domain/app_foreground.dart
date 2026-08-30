/// Whether the app is in the foreground.
///
/// Exists for recurring work whose results nobody can see while the app is
/// hidden. Such work should park rather than keep running, because it costs a
/// laptop real cycles to produce answers that will be recomputed on return.
abstract class AppForeground {
  /// Whether the app is currently visible to the user.
  bool get isForeground;

  /// Emits on every change to [isForeground].
  Stream<bool> get changes;

  void dispose();
}

/// An [AppForeground] that never parks.
///
/// The default wherever there is no running app to observe: tests, headless
/// use, and anything constructed before the binding exists. Defaulting to
/// foreground keeps the parking opt-in, so a missed wiring degrades to the
/// behavior that was there before rather than to silence.
class const AlwaysForeground() implements AppForeground {
  @override
  bool get isForeground => true;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  void dispose() {}
}
