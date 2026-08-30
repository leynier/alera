/// How far a restored snapshot has been written into the emulator.
///
/// A restore is drained over several frames, so the surface needs to know how
/// far along it is to show something better than history scrolling past.
class const TerminalRestoreProgress({
  required final int writtenChars,
  required final int totalChars,
}) {
  double get fraction {
    if (totalChars <= 0) {
      return 1;
    }
    final value = writtenChars / totalChars;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  @override
  bool operator ==(Object other) =>
      other is TerminalRestoreProgress &&
      other.writtenChars == writtenChars &&
      other.totalChars == totalChars;

  @override
  int get hashCode => Object.hash(writtenChars, totalChars);
}
