/// State of a host as `mobile.hosts.list` reports it in `status`, mirroring
/// the desktop host state. A runtime that predates the field, or a value this
/// build does not know, reads as [unknown], which counts as ready so an older
/// runtime keeps every host selectable.
enum MobileWorkspaceHostStatus {
  needsSetup,
  installing,
  disconnected,
  offline,
  connecting,
  connected,
  error,
  unknown;

  static MobileWorkspaceHostStatus parse(String? value) {
    return switch (value?.trim()) {
      'needsSetup' => MobileWorkspaceHostStatus.needsSetup,
      'installing' => MobileWorkspaceHostStatus.installing,
      'disconnected' => MobileWorkspaceHostStatus.disconnected,
      'offline' => MobileWorkspaceHostStatus.offline,
      'connecting' => MobileWorkspaceHostStatus.connecting,
      'connected' => MobileWorkspaceHostStatus.connected,
      'error' => MobileWorkspaceHostStatus.error,
      _ => MobileWorkspaceHostStatus.unknown,
    };
  }

  /// Badge text for the state, or null when there is nothing to say.
  String? get label => switch (this) {
    MobileWorkspaceHostStatus.needsSetup => 'Needs Setup',
    MobileWorkspaceHostStatus.installing => 'Installing…',
    MobileWorkspaceHostStatus.disconnected => 'Not Connected',
    MobileWorkspaceHostStatus.offline => 'Offline',
    MobileWorkspaceHostStatus.connecting => 'Connecting…',
    MobileWorkspaceHostStatus.connected => 'Connected',
    MobileWorkspaceHostStatus.error => 'Error',
    MobileWorkspaceHostStatus.unknown => null,
  };

  /// Whether a workspace can be created there. The runtime connects to an
  /// offline or idle host on demand, so only a host without a working Alera
  /// runtime blocks creation.
  bool get isReady => switch (this) {
    MobileWorkspaceHostStatus.needsSetup ||
    MobileWorkspaceHostStatus.installing ||
    MobileWorkspaceHostStatus.error => false,
    _ => true,
  };
}
