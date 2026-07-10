/// Authentication state of a forge's official CLI. Authentication is delegated
/// entirely to the CLI (`gh auth login`, `az login`); Alera only reads status.
enum ForgeAuthStatus {
  /// The CLI is installed and authenticated for the target host.
  authenticated,

  /// The CLI is installed but not logged in for the target host.
  notAuthenticated,

  /// The CLI (or a required extension) is not installed or not on PATH.
  cliMissing,

  /// Status could not be determined (transport error, unexpected output).
  unknown,
}
