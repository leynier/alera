// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_policy_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runPolicyRepository)
final runPolicyRepositoryProvider = RunPolicyRepositoryProvider._();

final class RunPolicyRepositoryProvider
    extends
        $FunctionalProvider<
          RuntimeRunPolicyRepository,
          RuntimeRunPolicyRepository,
          RuntimeRunPolicyRepository
        >
    with $Provider<RuntimeRunPolicyRepository> {
  RunPolicyRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runPolicyRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runPolicyRepositoryHash();

  @$internal
  @override
  $ProviderElement<RuntimeRunPolicyRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeRunPolicyRepository create(Ref ref) {
    return runPolicyRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeRunPolicyRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeRunPolicyRepository>(value),
    );
  }
}

String _$runPolicyRepositoryHash() =>
    r'659ed6813b383ff3eb2aa137f7c306b1f4d671eb';

/// Plans the user can review. Fetched on demand rather than watched: runs are
/// not a live surface in the app, and a plan only changes when someone acts.

@ProviderFor(runExecutionPolicies)
final runExecutionPoliciesProvider = RunExecutionPoliciesProvider._();

/// Plans the user can review. Fetched on demand rather than watched: runs are
/// not a live surface in the app, and a plan only changes when someone acts.

final class RunExecutionPoliciesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RunExecutionPolicy>>,
          List<RunExecutionPolicy>,
          FutureOr<List<RunExecutionPolicy>>
        >
    with
        $FutureModifier<List<RunExecutionPolicy>>,
        $FutureProvider<List<RunExecutionPolicy>> {
  /// Plans the user can review. Fetched on demand rather than watched: runs are
  /// not a live surface in the app, and a plan only changes when someone acts.
  RunExecutionPoliciesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runExecutionPoliciesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runExecutionPoliciesHash();

  @$internal
  @override
  $FutureProviderElement<List<RunExecutionPolicy>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<RunExecutionPolicy>> create(Ref ref) {
    return runExecutionPolicies(ref);
  }
}

String _$runExecutionPoliciesHash() =>
    r'dc59fd0d153be7a6b16da7fecd920fdf1cef7dad';
