// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resource_manager_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the resource panel is on screen. Drives the polling cadence.

@ProviderFor(ResourcePanelOpen)
final resourcePanelOpenProvider = ResourcePanelOpenProvider._();

/// Whether the resource panel is on screen. Drives the polling cadence.
final class ResourcePanelOpenProvider
    extends $NotifierProvider<ResourcePanelOpen, bool> {
  /// Whether the resource panel is on screen. Drives the polling cadence.
  ResourcePanelOpenProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'resourcePanelOpenProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$resourcePanelOpenHash();

  @$internal
  @override
  ResourcePanelOpen create() => ResourcePanelOpen();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$resourcePanelOpenHash() => r'bc22c6b74fdcbfc79dc5befcc04b43a1f8109d94';

/// Whether the resource panel is on screen. Drives the polling cadence.

abstract class _$ResourcePanelOpen extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(resourceSnapshot)
final resourceSnapshotProvider = ResourceSnapshotProvider._();

final class ResourceSnapshotProvider
    extends
        $FunctionalProvider<
          AsyncValue<ResourceSnapshot>,
          ResourceSnapshot,
          FutureOr<ResourceSnapshot>
        >
    with $FutureModifier<ResourceSnapshot>, $FutureProvider<ResourceSnapshot> {
  ResourceSnapshotProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'resourceSnapshotProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$resourceSnapshotHash();

  @$internal
  @override
  $FutureProviderElement<ResourceSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ResourceSnapshot> create(Ref ref) {
    return resourceSnapshot(ref);
  }
}

String _$resourceSnapshotHash() => r'f41238a4739e9ae38c3b0c9cecb1ad76ec9ccd10';

/// The snapshot projected onto the workbench tree, ready to render.

@ProviderFor(resourceTree)
final resourceTreeProvider = ResourceTreeFamily._();

/// The snapshot projected onto the workbench tree, ready to render.

final class ResourceTreeProvider
    extends $FunctionalProvider<ResourceTree, ResourceTree, ResourceTree>
    with $Provider<ResourceTree> {
  /// The snapshot projected onto the workbench tree, ready to render.
  ResourceTreeProvider._({
    required ResourceTreeFamily super.from,
    required ResourceSortColumn super.argument,
  }) : super(
         retry: null,
         name: r'resourceTreeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$resourceTreeHash();

  @override
  String toString() {
    return r'resourceTreeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ResourceTree> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ResourceTree create(Ref ref) {
    final argument = this.argument as ResourceSortColumn;
    return resourceTree(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ResourceTree value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ResourceTree>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ResourceTreeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$resourceTreeHash() => r'171b800b95589ee4f6b8a0db0c031b9639231da9';

/// The snapshot projected onto the workbench tree, ready to render.

final class ResourceTreeFamily extends $Family
    with $FunctionalFamilyOverride<ResourceTree, ResourceSortColumn> {
  ResourceTreeFamily._()
    : super(
        retry: null,
        name: r'resourceTreeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The snapshot projected onto the workbench tree, ready to render.

  ResourceTreeProvider call(ResourceSortColumn sortColumn) =>
      ResourceTreeProvider._(argument: sortColumn, from: this);

  @override
  String toString() => r'resourceTreeProvider';
}
