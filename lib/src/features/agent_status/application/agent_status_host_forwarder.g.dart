// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_status_host_forwarder.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Forwards agent status transitions to the runtime-host so it can run
/// push-on-idle orchestration message delivery and resolve @agent groups.
/// The host keys presence by terminal session id, which doubles as the
/// orchestration terminal handle.

@ProviderFor(agentStatusHostForwarder)
final agentStatusHostForwarderProvider = AgentStatusHostForwarderProvider._();

/// Forwards agent status transitions to the runtime-host so it can run
/// push-on-idle orchestration message delivery and resolve @agent groups.
/// The host keys presence by terminal session id, which doubles as the
/// orchestration terminal handle.

final class AgentStatusHostForwarderProvider
    extends
        $FunctionalProvider<
          AgentStatusHostForwarder,
          AgentStatusHostForwarder,
          AgentStatusHostForwarder
        >
    with $Provider<AgentStatusHostForwarder> {
  /// Forwards agent status transitions to the runtime-host so it can run
  /// push-on-idle orchestration message delivery and resolve @agent groups.
  /// The host keys presence by terminal session id, which doubles as the
  /// orchestration terminal handle.
  AgentStatusHostForwarderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentStatusHostForwarderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentStatusHostForwarderHash();

  @$internal
  @override
  $ProviderElement<AgentStatusHostForwarder> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentStatusHostForwarder create(Ref ref) {
    return agentStatusHostForwarder(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentStatusHostForwarder value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentStatusHostForwarder>(value),
    );
  }
}

String _$agentStatusHostForwarderHash() =>
    r'b2183e311105188ff4ce90e9c4a2736836cae91d';
