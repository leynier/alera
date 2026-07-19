// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_agent_expansion_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workspaceAgentExpansionRepository)
final workspaceAgentExpansionRepositoryProvider =
    WorkspaceAgentExpansionRepositoryProvider._();

final class WorkspaceAgentExpansionRepositoryProvider
    extends
        $FunctionalProvider<
          LocalWorkspaceAgentExpansionRepository,
          LocalWorkspaceAgentExpansionRepository,
          LocalWorkspaceAgentExpansionRepository
        >
    with $Provider<LocalWorkspaceAgentExpansionRepository> {
  WorkspaceAgentExpansionRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceAgentExpansionRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$workspaceAgentExpansionRepositoryHash();

  @$internal
  @override
  $ProviderElement<LocalWorkspaceAgentExpansionRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LocalWorkspaceAgentExpansionRepository create(Ref ref) {
    return workspaceAgentExpansionRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocalWorkspaceAgentExpansionRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<LocalWorkspaceAgentExpansionRepository>(value),
    );
  }
}

String _$workspaceAgentExpansionRepositoryHash() =>
    r'967bed48b73056a7ad23570f9dc8140b4360928a';

@ProviderFor(WorkspaceAgentExpansionController)
final workspaceAgentExpansionControllerProvider =
    WorkspaceAgentExpansionControllerFamily._();

final class WorkspaceAgentExpansionControllerProvider
    extends
        $AsyncNotifierProvider<WorkspaceAgentExpansionController, Set<String>> {
  WorkspaceAgentExpansionControllerProvider._({
    required WorkspaceAgentExpansionControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceAgentExpansionControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$workspaceAgentExpansionControllerHash();

  @override
  String toString() {
    return r'workspaceAgentExpansionControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspaceAgentExpansionController create() =>
      WorkspaceAgentExpansionController();

  @override
  bool operator ==(Object other) {
    return other is WorkspaceAgentExpansionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceAgentExpansionControllerHash() =>
    r'cdc990014ff3d3bd0b0b39b4c1f2cb7b4a80f99d';

final class WorkspaceAgentExpansionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceAgentExpansionController,
          AsyncValue<Set<String>>,
          Set<String>,
          FutureOr<Set<String>>,
          String
        > {
  WorkspaceAgentExpansionControllerFamily._()
    : super(
        retry: null,
        name: r'workspaceAgentExpansionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceAgentExpansionControllerProvider call(String hostId) =>
      WorkspaceAgentExpansionControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'workspaceAgentExpansionControllerProvider';
}

abstract class _$WorkspaceAgentExpansionController
    extends $AsyncNotifier<Set<String>> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<Set<String>> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Set<String>>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Set<String>>, Set<String>>,
              AsyncValue<Set<String>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
