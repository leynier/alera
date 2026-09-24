// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_pull_request_monitor_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workspacePullRequestMonitorLoader)
final workspacePullRequestMonitorLoaderProvider =
    WorkspacePullRequestMonitorLoaderProvider._();

final class WorkspacePullRequestMonitorLoaderProvider
    extends
        $FunctionalProvider<
          WorkspacePullRequestMonitorLoader,
          WorkspacePullRequestMonitorLoader,
          WorkspacePullRequestMonitorLoader
        >
    with $Provider<WorkspacePullRequestMonitorLoader> {
  WorkspacePullRequestMonitorLoaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspacePullRequestMonitorLoaderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$workspacePullRequestMonitorLoaderHash();

  @$internal
  @override
  $ProviderElement<WorkspacePullRequestMonitorLoader> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspacePullRequestMonitorLoader create(Ref ref) {
    return workspacePullRequestMonitorLoader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspacePullRequestMonitorLoader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspacePullRequestMonitorLoader>(
        value,
      ),
    );
  }
}

String _$workspacePullRequestMonitorLoaderHash() =>
    r'd7e7ca104e8dca739c1770121996783eba2dbecb';

@ProviderFor(workspacePullRequestMonitorConfiguration)
final workspacePullRequestMonitorConfigurationProvider =
    WorkspacePullRequestMonitorConfigurationProvider._();

final class WorkspacePullRequestMonitorConfigurationProvider
    extends
        $FunctionalProvider<
          WorkspacePullRequestMonitorConfiguration,
          WorkspacePullRequestMonitorConfiguration,
          WorkspacePullRequestMonitorConfiguration
        >
    with $Provider<WorkspacePullRequestMonitorConfiguration> {
  WorkspacePullRequestMonitorConfigurationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspacePullRequestMonitorConfigurationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$workspacePullRequestMonitorConfigurationHash();

  @$internal
  @override
  $ProviderElement<WorkspacePullRequestMonitorConfiguration> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspacePullRequestMonitorConfiguration create(Ref ref) {
    return workspacePullRequestMonitorConfiguration(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspacePullRequestMonitorConfiguration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<WorkspacePullRequestMonitorConfiguration>(value),
    );
  }
}

String _$workspacePullRequestMonitorConfigurationHash() =>
    r'b3b6b7e4b4a94c6b98d9c4b525cbfa0fc2b60d9d';

/// One timer and one refresh pipeline for every workspace. Provider calls are
/// grouped by repository in [WorkspacePullRequestMonitorLoader], and the timer
/// parks while the app is hidden unless failure notifications are enabled.

@ProviderFor(WorkspacePullRequestMonitorController)
final workspacePullRequestMonitorControllerProvider =
    WorkspacePullRequestMonitorControllerProvider._();

/// One timer and one refresh pipeline for every workspace. Provider calls are
/// grouped by repository in [WorkspacePullRequestMonitorLoader], and the timer
/// parks while the app is hidden unless failure notifications are enabled.
final class WorkspacePullRequestMonitorControllerProvider
    extends
        $NotifierProvider<
          WorkspacePullRequestMonitorController,
          WorkspacePullRequestMonitorState
        > {
  /// One timer and one refresh pipeline for every workspace. Provider calls are
  /// grouped by repository in [WorkspacePullRequestMonitorLoader], and the timer
  /// parks while the app is hidden unless failure notifications are enabled.
  WorkspacePullRequestMonitorControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspacePullRequestMonitorControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$workspacePullRequestMonitorControllerHash();

  @$internal
  @override
  WorkspacePullRequestMonitorController create() =>
      WorkspacePullRequestMonitorController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspacePullRequestMonitorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspacePullRequestMonitorState>(
        value,
      ),
    );
  }
}

String _$workspacePullRequestMonitorControllerHash() =>
    r'5f7bc0c16f96007d8db2b1ff4f7526eb834404a5';

/// One timer and one refresh pipeline for every workspace. Provider calls are
/// grouped by repository in [WorkspacePullRequestMonitorLoader], and the timer
/// parks while the app is hidden unless failure notifications are enabled.

abstract class _$WorkspacePullRequestMonitorController
    extends $Notifier<WorkspacePullRequestMonitorState> {
  WorkspacePullRequestMonitorState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              WorkspacePullRequestMonitorState,
              WorkspacePullRequestMonitorState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                WorkspacePullRequestMonitorState,
                WorkspacePullRequestMonitorState
              >,
              WorkspacePullRequestMonitorState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(workspacePullRequestSummary)
final workspacePullRequestSummaryProvider =
    WorkspacePullRequestSummaryFamily._();

final class WorkspacePullRequestSummaryProvider
    extends
        $FunctionalProvider<
          WorkspacePullRequestSummary?,
          WorkspacePullRequestSummary?,
          WorkspacePullRequestSummary?
        >
    with $Provider<WorkspacePullRequestSummary?> {
  WorkspacePullRequestSummaryProvider._({
    required WorkspacePullRequestSummaryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspacePullRequestSummaryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspacePullRequestSummaryHash();

  @override
  String toString() {
    return r'workspacePullRequestSummaryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<WorkspacePullRequestSummary?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspacePullRequestSummary? create(Ref ref) {
    final argument = this.argument as String;
    return workspacePullRequestSummary(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspacePullRequestSummary? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspacePullRequestSummary?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspacePullRequestSummaryProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspacePullRequestSummaryHash() =>
    r'34d2c215c2e39426fceefe7274280cdd3538f1cb';

final class WorkspacePullRequestSummaryFamily extends $Family
    with $FunctionalFamilyOverride<WorkspacePullRequestSummary?, String> {
  WorkspacePullRequestSummaryFamily._()
    : super(
        retry: null,
        name: r'workspacePullRequestSummaryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspacePullRequestSummaryProvider call(String workspaceId) =>
      WorkspacePullRequestSummaryProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'workspacePullRequestSummaryProvider';
}
