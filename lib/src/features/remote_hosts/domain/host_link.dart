/// Lifecycle of the hub's persistent link to one remote host, as reported by
/// `hostLink.status` and `hostLinkChanged`.
enum HostLinkPhase {
  disconnected,
  connecting,
  attached,
  failed;

  static HostLinkPhase parse(Object? value) {
    return switch (value) {
      'connecting' => HostLinkPhase.connecting,
      'attached' => HostLinkPhase.attached,
      'failed' => HostLinkPhase.failed,
      _ => HostLinkPhase.disconnected,
    };
  }
}

/// What the satellite announced when the link attached.
class const HostLinkAttachment({
  required final String runtimeDir,
  required final String platform,
  required final String arch,
  final String? hostVersion,
  final List<String> runtimeCapabilities = const <String>[],
}) {
  factory fromJson(Map<String, Object?> json) {
    final capabilities = json['runtimeCapabilities'];
    return HostLinkAttachment(
      runtimeDir: (json['runtimeDir'] as String?) ?? '',
      platform: (json['platform'] as String?) ?? '',
      arch: (json['arch'] as String?) ?? '',
      hostVersion: json['hostVersion'] as String?,
      runtimeCapabilities: capabilities is List
          ? List<String>.unmodifiableOf(capabilities.whereType<String>())
          : const <String>[],
    );
  }

  bool hasCapability(String capability) =>
      runtimeCapabilities.contains(capability);
}

class const HostLinkState({
  required final String hostId,
  required final HostLinkPhase phase,
  final HostLinkAttachment? attachment,
  final String? error,
}) {
  factory fromJson(Map<String, Object?> json) {
    final attachment = json['attachment'];
    return HostLinkState(
      hostId: (json['hostId'] as String?) ?? '',
      phase: HostLinkPhase.parse(json['state']),
      attachment: attachment is Map
          ? HostLinkAttachment.fromJson(Map<String, Object?>.from(attachment))
          : null,
      error: json['error'] as String?,
    );
  }

  bool get isAttached => phase == HostLinkPhase.attached;
}

Map<String, HostLinkState> hostLinkStatesById(Iterable<HostLinkState> states) {
  return Map<String, HostLinkState>.unmodifiableOf(<String, HostLinkState>{
    for (final state in states) state.hostId: state,
  });
}
