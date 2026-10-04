// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(automationRepository)
final automationRepositoryProvider = AutomationRepositoryProvider._();

final class AutomationRepositoryProvider
    extends
        $FunctionalProvider<
          RuntimeAutomationRepository,
          RuntimeAutomationRepository,
          RuntimeAutomationRepository
        >
    with $Provider<RuntimeAutomationRepository> {
  AutomationRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationRepositoryHash();

  @$internal
  @override
  $ProviderElement<RuntimeAutomationRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeAutomationRepository create(Ref ref) {
    return automationRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeAutomationRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeAutomationRepository>(value),
    );
  }
}

String _$automationRepositoryHash() =>
    r'fc00105a888176b8459c27e7d6785b0192c618a1';

/// The whole catalog of the connected runtime, trash included, so scope,
/// bucket and filter changes never wait on the network. Every lifecycle event
/// and every runtime reconnection reloads it; Riverpod keeps the previous
/// list visible while that happens.

@ProviderFor(AutomationCatalog)
final automationCatalogProvider = AutomationCatalogProvider._();

/// The whole catalog of the connected runtime, trash included, so scope,
/// bucket and filter changes never wait on the network. Every lifecycle event
/// and every runtime reconnection reloads it; Riverpod keeps the previous
/// list visible while that happens.
final class AutomationCatalogProvider
    extends $AsyncNotifierProvider<AutomationCatalog, List<AutomationRecord>> {
  /// The whole catalog of the connected runtime, trash included, so scope,
  /// bucket and filter changes never wait on the network. Every lifecycle event
  /// and every runtime reconnection reloads it; Riverpod keeps the previous
  /// list visible while that happens.
  AutomationCatalogProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationCatalogProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationCatalogHash();

  @$internal
  @override
  AutomationCatalog create() => AutomationCatalog();
}

String _$automationCatalogHash() => r'6e152ac58c521ae5258d5deffdda18f553aa8042';

/// The whole catalog of the connected runtime, trash included, so scope,
/// bucket and filter changes never wait on the network. Every lifecycle event
/// and every runtime reconnection reloads it; Riverpod keeps the previous
/// list visible while that happens.

abstract class _$AutomationCatalog
    extends $AsyncNotifier<List<AutomationRecord>> {
  FutureOr<List<AutomationRecord>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<AutomationRecord>>, List<AutomationRecord>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<AutomationRecord>>,
                List<AutomationRecord>
              >,
              AsyncValue<List<AutomationRecord>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(AutomationDetailController)
final automationDetailControllerProvider = AutomationDetailControllerFamily._();

final class AutomationDetailControllerProvider
    extends
        $AsyncNotifierProvider<AutomationDetailController, AutomationDetail> {
  AutomationDetailControllerProvider._({
    required AutomationDetailControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'automationDetailControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$automationDetailControllerHash();

  @override
  String toString() {
    return r'automationDetailControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AutomationDetailController create() => AutomationDetailController();

  @override
  bool operator ==(Object other) {
    return other is AutomationDetailControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$automationDetailControllerHash() =>
    r'1986f7ef4c4cefde9b199e550e9d5e7ab50171a8';

final class AutomationDetailControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AutomationDetailController,
          AsyncValue<AutomationDetail>,
          AutomationDetail,
          FutureOr<AutomationDetail>,
          String
        > {
  AutomationDetailControllerFamily._()
    : super(
        retry: null,
        name: r'automationDetailControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AutomationDetailControllerProvider call(String id) =>
      AutomationDetailControllerProvider._(argument: id, from: this);

  @override
  String toString() => r'automationDetailControllerProvider';
}

abstract class _$AutomationDetailController
    extends $AsyncNotifier<AutomationDetail> {
  late final _$args = ref.$arg as String;
  String get id => _$args;

  FutureOr<AutomationDetail> build(String id);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<AutomationDetail>, AutomationDetail>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AutomationDetail>, AutomationDetail>,
              AsyncValue<AutomationDetail>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Recent runs across every automation, for the workspace scope's "Runs In
/// This Workspace" list. Run ownership never creates a scheduling association.

@ProviderFor(AutomationRecentRuns)
final automationRecentRunsProvider = AutomationRecentRunsProvider._();

/// Recent runs across every automation, for the workspace scope's "Runs In
/// This Workspace" list. Run ownership never creates a scheduling association.
final class AutomationRecentRunsProvider
    extends
        $AsyncNotifierProvider<
          AutomationRecentRuns,
          List<AutomationRunRecord>
        > {
  /// Recent runs across every automation, for the workspace scope's "Runs In
  /// This Workspace" list. Run ownership never creates a scheduling association.
  AutomationRecentRunsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationRecentRunsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationRecentRunsHash();

  @$internal
  @override
  AutomationRecentRuns create() => AutomationRecentRuns();
}

String _$automationRecentRunsHash() =>
    r'cb8d2f9e0b242168d6bc17abf45c6530cb60782d';

/// Recent runs across every automation, for the workspace scope's "Runs In
/// This Workspace" list. Run ownership never creates a scheduling association.

abstract class _$AutomationRecentRuns
    extends $AsyncNotifier<List<AutomationRunRecord>> {
  FutureOr<List<AutomationRunRecord>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<AutomationRunRecord>>,
              List<AutomationRunRecord>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<AutomationRunRecord>>,
                List<AutomationRunRecord>
              >,
              AsyncValue<List<AutomationRunRecord>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(AutomationRuntimeCapabilities)
final automationRuntimeCapabilitiesProvider =
    AutomationRuntimeCapabilitiesProvider._();

final class AutomationRuntimeCapabilitiesProvider
    extends
        $AsyncNotifierProvider<
          AutomationRuntimeCapabilities,
          AutomationCapabilities
        > {
  AutomationRuntimeCapabilitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationRuntimeCapabilitiesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationRuntimeCapabilitiesHash();

  @$internal
  @override
  AutomationRuntimeCapabilities create() => AutomationRuntimeCapabilities();
}

String _$automationRuntimeCapabilitiesHash() =>
    r'e0bcd90f5cacd4a03fabf42fe23de051e65b7eee';

abstract class _$AutomationRuntimeCapabilities
    extends $AsyncNotifier<AutomationCapabilities> {
  FutureOr<AutomationCapabilities> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<AutomationCapabilities>, AutomationCapabilities>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AutomationCapabilities>,
                AutomationCapabilities
              >,
              AsyncValue<AutomationCapabilities>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Tag ids to names, refreshed with the catalog.

@ProviderFor(automationTagNames)
final automationTagNamesProvider = AutomationTagNamesProvider._();

/// Tag ids to names, refreshed with the catalog.

final class AutomationTagNamesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, String>>,
          Map<String, String>,
          FutureOr<Map<String, String>>
        >
    with
        $FutureModifier<Map<String, String>>,
        $FutureProvider<Map<String, String>> {
  /// Tag ids to names, refreshed with the catalog.
  AutomationTagNamesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationTagNamesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationTagNamesHash();

  @$internal
  @override
  $FutureProviderElement<Map<String, String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, String>> create(Ref ref) {
    return automationTagNames(ref);
  }
}

String _$automationTagNamesHash() =>
    r'b98ef92273b1d328f8d771125aa8d82b9e51f364';
