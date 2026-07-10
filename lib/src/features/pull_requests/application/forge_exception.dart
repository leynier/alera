/// Typed failures raised by a `ForgeProvider`. Providers translate CLI exit
/// codes and stderr into these instead of leaking raw strings upward, so a
/// genuine "no review" / "no checks" (a null / empty list) is never confused
/// with an error.
sealed class ForgeException implements Exception {
  const ForgeException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The CLI is installed but not authenticated for the target host.
class ForgeNotAuthenticated extends ForgeException {
  const ForgeNotAuthenticated([super.message = 'Not authenticated']);
}

/// The CLI (or a required extension) is missing from PATH.
class ForgeCliMissing extends ForgeException {
  const ForgeCliMissing([super.message = 'CLI not found']);
}

/// The CLI ran but the request failed (transport, unexpected output, ...).
class ForgeRequestFailed extends ForgeException {
  const ForgeRequestFailed(super.message);
}
