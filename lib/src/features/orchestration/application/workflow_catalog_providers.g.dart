// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workflow_catalog_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workflowCatalogRepository)
final workflowCatalogRepositoryProvider = WorkflowCatalogRepositoryProvider._();

final class WorkflowCatalogRepositoryProvider
    extends
        $FunctionalProvider<
          WorkflowCatalogRepository,
          WorkflowCatalogRepository,
          WorkflowCatalogRepository
        >
    with $Provider<WorkflowCatalogRepository> {
  WorkflowCatalogRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workflowCatalogRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workflowCatalogRepositoryHash();

  @$internal
  @override
  $ProviderElement<WorkflowCatalogRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkflowCatalogRepository create(Ref ref) {
    return workflowCatalogRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkflowCatalogRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkflowCatalogRepository>(value),
    );
  }
}

String _$workflowCatalogRepositoryHash() =>
    r'af6e954269e1df7eb9777988af7cd6acddd4e8c4';

@ProviderFor(WorkflowCatalogDraft)
final workflowCatalogDraftProvider = WorkflowCatalogDraftProvider._();

final class WorkflowCatalogDraftProvider
    extends $NotifierProvider<WorkflowCatalogDraft, WorkflowCatalogEdit?> {
  WorkflowCatalogDraftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workflowCatalogDraftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workflowCatalogDraftHash();

  @$internal
  @override
  WorkflowCatalogDraft create() => WorkflowCatalogDraft();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkflowCatalogEdit? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkflowCatalogEdit?>(value),
    );
  }
}

String _$workflowCatalogDraftHash() =>
    r'0fe450e76d4cb4b16bbbb29f74dc5cec1aaf5458';

abstract class _$WorkflowCatalogDraft extends $Notifier<WorkflowCatalogEdit?> {
  WorkflowCatalogEdit? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<WorkflowCatalogEdit?, WorkflowCatalogEdit?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WorkflowCatalogEdit?, WorkflowCatalogEdit?>,
              WorkflowCatalogEdit?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
