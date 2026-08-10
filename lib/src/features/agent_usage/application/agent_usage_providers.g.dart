// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_usage_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentUsageSnapshotCache)
final agentUsageSnapshotCacheProvider = AgentUsageSnapshotCacheProvider._();

final class AgentUsageSnapshotCacheProvider
    extends
        $FunctionalProvider<
          AgentUsageSnapshotCache,
          AgentUsageSnapshotCache,
          AgentUsageSnapshotCache
        >
    with $Provider<AgentUsageSnapshotCache> {
  AgentUsageSnapshotCacheProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentUsageSnapshotCacheProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentUsageSnapshotCacheHash();

  @$internal
  @override
  $ProviderElement<AgentUsageSnapshotCache> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentUsageSnapshotCache create(Ref ref) {
    return agentUsageSnapshotCache(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentUsageSnapshotCache value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentUsageSnapshotCache>(value),
    );
  }
}

String _$agentUsageSnapshotCacheHash() =>
    r'43ee682363afc0bd89cfde79149b8741abd857cc';

@ProviderFor(agentUsageLoader)
final agentUsageLoaderProvider = AgentUsageLoaderProvider._();

final class AgentUsageLoaderProvider
    extends
        $FunctionalProvider<
          AgentUsageLoader,
          AgentUsageLoader,
          AgentUsageLoader
        >
    with $Provider<AgentUsageLoader> {
  AgentUsageLoaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentUsageLoaderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentUsageLoaderHash();

  @$internal
  @override
  $ProviderElement<AgentUsageLoader> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AgentUsageLoader create(Ref ref) {
    return agentUsageLoader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentUsageLoader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentUsageLoader>(value),
    );
  }
}

String _$agentUsageLoaderHash() => r'572f03a3a78e70bb701d8d2bd3bd380756acadfd';

@ProviderFor(AgentUsage)
final agentUsageProvider = AgentUsageFamily._();

final class AgentUsageProvider
    extends $AsyncNotifierProvider<AgentUsage, AgentUsageState> {
  AgentUsageProvider._({
    required AgentUsageFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'agentUsageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentUsageHash();

  @override
  String toString() {
    return r'agentUsageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentUsage create() => AgentUsage();

  @override
  bool operator ==(Object other) {
    return other is AgentUsageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentUsageHash() => r'c04bb8fafc41a58b4f96a160d5ccd25d08b49d4d';

final class AgentUsageFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentUsage,
          AsyncValue<AgentUsageState>,
          AgentUsageState,
          FutureOr<AgentUsageState>,
          int
        > {
  AgentUsageFamily._()
    : super(
        retry: null,
        name: r'agentUsageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentUsageProvider call(int days) =>
      AgentUsageProvider._(argument: days, from: this);

  @override
  String toString() => r'agentUsageProvider';
}

abstract class _$AgentUsage extends $AsyncNotifier<AgentUsageState> {
  late final _$args = ref.$arg as int;
  int get days => _$args;

  FutureOr<AgentUsageState> build(int days);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AgentUsageState>, AgentUsageState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AgentUsageState>, AgentUsageState>,
              AsyncValue<AgentUsageState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
