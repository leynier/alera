// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workflow_lifecycle_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workflowLifecycleRepository)
final workflowLifecycleRepositoryProvider =
    WorkflowLifecycleRepositoryProvider._();

final class WorkflowLifecycleRepositoryProvider
    extends
        $FunctionalProvider<
          WorkflowLifecycleRepository,
          WorkflowLifecycleRepository,
          WorkflowLifecycleRepository
        >
    with $Provider<WorkflowLifecycleRepository> {
  WorkflowLifecycleRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workflowLifecycleRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workflowLifecycleRepositoryHash();

  @$internal
  @override
  $ProviderElement<WorkflowLifecycleRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkflowLifecycleRepository create(Ref ref) {
    return workflowLifecycleRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkflowLifecycleRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkflowLifecycleRepository>(value),
    );
  }
}

String _$workflowLifecycleRepositoryHash() =>
    r'ffa6158aa478bf51e41ad35284b1b6bb3c5e008d';
