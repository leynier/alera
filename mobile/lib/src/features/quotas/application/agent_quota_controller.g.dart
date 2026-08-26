// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_quota_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AgentQuotaController)
final agentQuotaControllerProvider = AgentQuotaControllerFamily._();

final class AgentQuotaControllerProvider
    extends $AsyncNotifierProvider<AgentQuotaController, QuotaSnapshotState> {
  AgentQuotaControllerProvider._({
    required AgentQuotaControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentQuotaControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentQuotaControllerHash();

  @override
  String toString() {
    return r'agentQuotaControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentQuotaController create() => AgentQuotaController();

  @override
  bool operator ==(Object other) {
    return other is AgentQuotaControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentQuotaControllerHash() =>
    r'10774784fda8b5142cb3d81023ee3c8693e03124';

final class AgentQuotaControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentQuotaController,
          AsyncValue<QuotaSnapshotState>,
          QuotaSnapshotState,
          FutureOr<QuotaSnapshotState>,
          String
        > {
  AgentQuotaControllerFamily._()
    : super(
        retry: null,
        name: r'agentQuotaControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentQuotaControllerProvider call(String hostId) =>
      AgentQuotaControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'agentQuotaControllerProvider';
}

abstract class _$AgentQuotaController
    extends $AsyncNotifier<QuotaSnapshotState> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<QuotaSnapshotState> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<QuotaSnapshotState>, QuotaSnapshotState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<QuotaSnapshotState>, QuotaSnapshotState>,
              AsyncValue<QuotaSnapshotState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
