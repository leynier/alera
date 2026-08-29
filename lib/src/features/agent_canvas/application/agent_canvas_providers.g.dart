// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_canvas_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(agentCanvasRepository)
final agentCanvasRepositoryProvider = AgentCanvasRepositoryProvider._();

final class AgentCanvasRepositoryProvider
    extends
        $FunctionalProvider<
          RuntimeAgentCanvasRepository,
          RuntimeAgentCanvasRepository,
          RuntimeAgentCanvasRepository
        >
    with $Provider<RuntimeAgentCanvasRepository> {
  AgentCanvasRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentCanvasRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentCanvasRepositoryHash();

  @$internal
  @override
  $ProviderElement<RuntimeAgentCanvasRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeAgentCanvasRepository create(Ref ref) {
    return agentCanvasRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeAgentCanvasRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeAgentCanvasRepository>(value),
    );
  }
}

String _$agentCanvasRepositoryHash() =>
    r'7a9a54164d664f1be54dbf77471d27d8940dba38';

@ProviderFor(agentCanvases)
final agentCanvasesProvider = AgentCanvasesFamily._();

final class AgentCanvasesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentCanvas>>,
          List<AgentCanvas>,
          Stream<List<AgentCanvas>>
        >
    with
        $FutureModifier<List<AgentCanvas>>,
        $StreamProvider<List<AgentCanvas>> {
  AgentCanvasesProvider._({
    required AgentCanvasesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentCanvasesProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentCanvasesHash();

  @override
  String toString() {
    return r'agentCanvasesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<AgentCanvas>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<AgentCanvas>> create(Ref ref) {
    final argument = this.argument as String;
    return agentCanvases(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentCanvasesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentCanvasesHash() => r'd7e122eb93445b6fedc1113ec68b4e3f9d170907';

final class AgentCanvasesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<AgentCanvas>>, String> {
  AgentCanvasesFamily._()
    : super(
        retry: null,
        name: r'agentCanvasesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  AgentCanvasesProvider call(String workspaceId) =>
      AgentCanvasesProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'agentCanvasesProvider';
}

@ProviderFor(AgentCanvasSelection)
final agentCanvasSelectionProvider = AgentCanvasSelectionFamily._();

final class AgentCanvasSelectionProvider
    extends $NotifierProvider<AgentCanvasSelection, String?> {
  AgentCanvasSelectionProvider._({
    required AgentCanvasSelectionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentCanvasSelectionProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentCanvasSelectionHash();

  @override
  String toString() {
    return r'agentCanvasSelectionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentCanvasSelection create() => AgentCanvasSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentCanvasSelectionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentCanvasSelectionHash() =>
    r'1fe9fa2762b405dc1d37ce62d83ebfd3be62773c';

final class AgentCanvasSelectionFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentCanvasSelection,
          String?,
          String?,
          String?,
          String
        > {
  AgentCanvasSelectionFamily._()
    : super(
        retry: null,
        name: r'agentCanvasSelectionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  AgentCanvasSelectionProvider call(String workspaceId) =>
      AgentCanvasSelectionProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'agentCanvasSelectionProvider';
}

abstract class _$AgentCanvasSelection extends $Notifier<String?> {
  late final _$args = ref.$arg as String;
  String get workspaceId => _$args;

  String? build(String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(agentCanvasCapabilities)
final agentCanvasCapabilitiesProvider = AgentCanvasCapabilitiesProvider._();

final class AgentCanvasCapabilitiesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, Object?>>,
          Map<String, Object?>,
          FutureOr<Map<String, Object?>>
        >
    with
        $FutureModifier<Map<String, Object?>>,
        $FutureProvider<Map<String, Object?>> {
  AgentCanvasCapabilitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentCanvasCapabilitiesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentCanvasCapabilitiesHash();

  @$internal
  @override
  $FutureProviderElement<Map<String, Object?>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, Object?>> create(Ref ref) {
    return agentCanvasCapabilities(ref);
  }
}

String _$agentCanvasCapabilitiesHash() =>
    r'0529998057d584aaf729bc2d248be36be9f6efec';

@ProviderFor(agentCanvasRuntimeSync)
final agentCanvasRuntimeSyncProvider = AgentCanvasRuntimeSyncProvider._();

final class AgentCanvasRuntimeSyncProvider
    extends
        $FunctionalProvider<
          AgentCanvasRuntimeSync,
          AgentCanvasRuntimeSync,
          AgentCanvasRuntimeSync
        >
    with $Provider<AgentCanvasRuntimeSync> {
  AgentCanvasRuntimeSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentCanvasRuntimeSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentCanvasRuntimeSyncHash();

  @$internal
  @override
  $ProviderElement<AgentCanvasRuntimeSync> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentCanvasRuntimeSync create(Ref ref) {
    return agentCanvasRuntimeSync(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentCanvasRuntimeSync value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentCanvasRuntimeSync>(value),
    );
  }
}

String _$agentCanvasRuntimeSyncHash() =>
    r'fa101827e5b7eae40cab6ceaf81adca0e2ac589f';
