/// Typed failures raised by a `ForgeProvider`. Providers translate CLI exit
/// codes and stderr into these instead of leaking raw strings upward, so a
/// genuine "no review" / "no checks" (a null / empty list) is never confused
/// with an error.
sealed class const ForgeException(final String message) implements Exception {
  @override
  String toString() => '$runtimeType: $message';
}

/// The CLI is installed but not authenticated for the target host.
class const ForgeNotAuthenticated([super.message = 'Not authenticated'])
    extends ForgeException;

/// The CLI (or a required extension) is missing from PATH.
class const ForgeCliMissing([super.message = 'CLI not found'])
    extends ForgeException;

/// The CLI ran but the request failed (transport, unexpected output, ...).
class const ForgeRequestFailed(super.message) extends ForgeException;
