// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_panels_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspacePanelCapabilitiesController)
final workspacePanelCapabilitiesControllerProvider =
    WorkspacePanelCapabilitiesControllerFamily._();

final class WorkspacePanelCapabilitiesControllerProvider
    extends
        $AsyncNotifierProvider<
          WorkspacePanelCapabilitiesController,
          WorkspacePanelCapabilities
        > {
  WorkspacePanelCapabilitiesControllerProvider._({
    required WorkspacePanelCapabilitiesControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspacePanelCapabilitiesControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$workspacePanelCapabilitiesControllerHash();

  @override
  String toString() {
    return r'workspacePanelCapabilitiesControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspacePanelCapabilitiesController create() =>
      WorkspacePanelCapabilitiesController();

  @override
  bool operator ==(Object other) {
    return other is WorkspacePanelCapabilitiesControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspacePanelCapabilitiesControllerHash() =>
    r'37659e4f31284e06e55136e24925748b4c1b22ad';

final class WorkspacePanelCapabilitiesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspacePanelCapabilitiesController,
          AsyncValue<WorkspacePanelCapabilities>,
          WorkspacePanelCapabilities,
          FutureOr<WorkspacePanelCapabilities>,
          String
        > {
  WorkspacePanelCapabilitiesControllerFamily._()
    : super(
        retry: null,
        name: r'workspacePanelCapabilitiesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspacePanelCapabilitiesControllerProvider call(String hostId) =>
      WorkspacePanelCapabilitiesControllerProvider._(
        argument: hostId,
        from: this,
      );

  @override
  String toString() => r'workspacePanelCapabilitiesControllerProvider';
}

abstract class _$WorkspacePanelCapabilitiesController
    extends $AsyncNotifier<WorkspacePanelCapabilities> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<WorkspacePanelCapabilities> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<WorkspacePanelCapabilities>,
              WorkspacePanelCapabilities
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<WorkspacePanelCapabilities>,
                WorkspacePanelCapabilities
              >,
              AsyncValue<WorkspacePanelCapabilities>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(SelectedWorkspacePanelController)
final selectedWorkspacePanelControllerProvider =
    SelectedWorkspacePanelControllerFamily._();

final class SelectedWorkspacePanelControllerProvider
    extends
        $NotifierProvider<
          SelectedWorkspacePanelController,
          WorkspacePanelDestination
        > {
  SelectedWorkspacePanelControllerProvider._({
    required SelectedWorkspacePanelControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'selectedWorkspacePanelControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$selectedWorkspacePanelControllerHash();

  @override
  String toString() {
    return r'selectedWorkspacePanelControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SelectedWorkspacePanelController create() =>
      SelectedWorkspacePanelController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspacePanelDestination value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspacePanelDestination>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SelectedWorkspacePanelControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$selectedWorkspacePanelControllerHash() =>
    r'a1c1d01b53430a5bb769ce255b902ea97f970f39';

final class SelectedWorkspacePanelControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SelectedWorkspacePanelController,
          WorkspacePanelDestination,
          WorkspacePanelDestination,
          WorkspacePanelDestination,
          (String, String)
        > {
  SelectedWorkspacePanelControllerFamily._()
    : super(
        retry: null,
        name: r'selectedWorkspacePanelControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SelectedWorkspacePanelControllerProvider call(
    String hostId,
    String workspaceId,
  ) => SelectedWorkspacePanelControllerProvider._(
    argument: (hostId, workspaceId),
    from: this,
  );

  @override
  String toString() => r'selectedWorkspacePanelControllerProvider';
}

abstract class _$SelectedWorkspacePanelController
    extends $Notifier<WorkspacePanelDestination> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  WorkspacePanelDestination build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<WorkspacePanelDestination, WorkspacePanelDestination>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WorkspacePanelDestination, WorkspacePanelDestination>,
              WorkspacePanelDestination,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
