// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_checkout_selection.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceCheckoutSelection)
final workspaceCheckoutSelectionProvider = WorkspaceCheckoutSelectionFamily._();

final class WorkspaceCheckoutSelectionProvider
    extends $NotifierProvider<WorkspaceCheckoutSelection, String?> {
  WorkspaceCheckoutSelectionProvider._({
    required WorkspaceCheckoutSelectionFamily super.from,
    required (String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'workspaceCheckoutSelectionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceCheckoutSelectionHash();

  @override
  String toString() {
    return r'workspaceCheckoutSelectionProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  WorkspaceCheckoutSelection create() => WorkspaceCheckoutSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceCheckoutSelectionProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceCheckoutSelectionHash() =>
    r'0e08a93d3573f295a5551d1d93a5d878e98a1b94';

final class WorkspaceCheckoutSelectionFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceCheckoutSelection,
          String?,
          String?,
          String?,
          (String, String?)
        > {
  WorkspaceCheckoutSelectionFamily._()
    : super(
        retry: null,
        name: r'workspaceCheckoutSelectionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceCheckoutSelectionProvider call(
    String runtimeHostId,
    String? initialCheckoutHostId,
  ) => WorkspaceCheckoutSelectionProvider._(
    argument: (runtimeHostId, initialCheckoutHostId),
    from: this,
  );

  @override
  String toString() => r'workspaceCheckoutSelectionProvider';
}

abstract class _$WorkspaceCheckoutSelection extends $Notifier<String?> {
  late final _$args = ref.$arg as (String, String?);
  String get runtimeHostId => _$args.$1;
  String? get initialCheckoutHostId => _$args.$2;

  String? build(String runtimeHostId, String? initialCheckoutHostId);
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
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

@ProviderFor(workspaceCheckoutOptions)
final workspaceCheckoutOptionsProvider = WorkspaceCheckoutOptionsFamily._();

final class WorkspaceCheckoutOptionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ProjectCheckoutSummary>>,
          List<ProjectCheckoutSummary>,
          FutureOr<List<ProjectCheckoutSummary>>
        >
    with
        $FutureModifier<List<ProjectCheckoutSummary>>,
        $FutureProvider<List<ProjectCheckoutSummary>> {
  WorkspaceCheckoutOptionsProvider._({
    required WorkspaceCheckoutOptionsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'workspaceCheckoutOptionsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceCheckoutOptionsHash();

  @override
  String toString() {
    return r'workspaceCheckoutOptionsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<ProjectCheckoutSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ProjectCheckoutSummary>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return workspaceCheckoutOptions(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceCheckoutOptionsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceCheckoutOptionsHash() =>
    r'dbb74200a58af04e6428f3132d36b1936715040a';

final class WorkspaceCheckoutOptionsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<ProjectCheckoutSummary>>,
          (String, String)
        > {
  WorkspaceCheckoutOptionsFamily._()
    : super(
        retry: null,
        name: r'workspaceCheckoutOptionsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceCheckoutOptionsProvider call(
    String runtimeHostId,
    String projectId,
  ) => WorkspaceCheckoutOptionsProvider._(
    argument: (runtimeHostId, projectId),
    from: this,
  );

  @override
  String toString() => r'workspaceCheckoutOptionsProvider';
}

@ProviderFor(PromptLocalAttachments)
final promptLocalAttachmentsProvider = PromptLocalAttachmentsFamily._();

final class PromptLocalAttachmentsProvider
    extends $NotifierProvider<PromptLocalAttachments, Set<String>> {
  PromptLocalAttachmentsProvider._({
    required PromptLocalAttachmentsFamily super.from,
    required (String, Set<String>) super.argument,
  }) : super(
         retry: null,
         name: r'promptLocalAttachmentsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$promptLocalAttachmentsHash();

  @override
  String toString() {
    return r'promptLocalAttachmentsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  PromptLocalAttachments create() => PromptLocalAttachments();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PromptLocalAttachmentsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$promptLocalAttachmentsHash() =>
    r'866f88df665fb3063585d6babaa433502e371af9';

final class PromptLocalAttachmentsFamily extends $Family
    with
        $ClassFamilyOverride<
          PromptLocalAttachments,
          Set<String>,
          Set<String>,
          Set<String>,
          (String, Set<String>)
        > {
  PromptLocalAttachmentsFamily._()
    : super(
        retry: null,
        name: r'promptLocalAttachmentsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PromptLocalAttachmentsProvider call(
    String runtimeHostId,
    Set<String> initialPaths,
  ) => PromptLocalAttachmentsProvider._(
    argument: (runtimeHostId, initialPaths),
    from: this,
  );

  @override
  String toString() => r'promptLocalAttachmentsProvider';
}

abstract class _$PromptLocalAttachments extends $Notifier<Set<String>> {
  late final _$args = ref.$arg as (String, Set<String>);
  String get runtimeHostId => _$args.$1;
  Set<String> get initialPaths => _$args.$2;

  Set<String> build(String runtimeHostId, Set<String> initialPaths);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
