// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_presence_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AgentPresenceController)
final agentPresenceControllerProvider = AgentPresenceControllerFamily._();

final class AgentPresenceControllerProvider
    extends
        $AsyncNotifierProvider<
          AgentPresenceController,
          List<AgentPresenceSummary>
        > {
  AgentPresenceControllerProvider._({
    required AgentPresenceControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentPresenceControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentPresenceControllerHash();

  @override
  String toString() {
    return r'agentPresenceControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentPresenceController create() => AgentPresenceController();

  @override
  bool operator ==(Object other) {
    return other is AgentPresenceControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentPresenceControllerHash() =>
    r'98602edd9d75e353e381f2f3757206fb1fe46a5c';

final class AgentPresenceControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentPresenceController,
          AsyncValue<List<AgentPresenceSummary>>,
          List<AgentPresenceSummary>,
          FutureOr<List<AgentPresenceSummary>>,
          String
        > {
  AgentPresenceControllerFamily._()
    : super(
        retry: null,
        name: r'agentPresenceControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentPresenceControllerProvider call(String hostId) =>
      AgentPresenceControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentPresenceControllerProvider';
}

abstract class _$AgentPresenceController
    extends $AsyncNotifier<List<AgentPresenceSummary>> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<List<AgentPresenceSummary>> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<AgentPresenceSummary>>,
              List<AgentPresenceSummary>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<AgentPresenceSummary>>,
                List<AgentPresenceSummary>
              >,
              AsyncValue<List<AgentPresenceSummary>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
