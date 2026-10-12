// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_actions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every run mutation goes through here. A retry of the same action reuses
/// its request id, so a response lost in transit replays the stored receipt
/// instead of acting twice. Holds no subscriptions, only these flags.

@ProviderFor(RunActions)
final runActionsProvider = RunActionsProvider._();

/// Every run mutation goes through here. A retry of the same action reuses
/// its request id, so a response lost in transit replays the stored receipt
/// instead of acting twice. Holds no subscriptions, only these flags.
final class RunActionsProvider
    extends $NotifierProvider<RunActions, RunActionsState> {
  /// Every run mutation goes through here. A retry of the same action reuses
  /// its request id, so a response lost in transit replays the stored receipt
  /// instead of acting twice. Holds no subscriptions, only these flags.
  RunActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runActionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runActionsHash();

  @$internal
  @override
  RunActions create() => RunActions();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RunActionsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RunActionsState>(value),
    );
  }
}

String _$runActionsHash() => r'3ac5f85fe17858be72a86034f5ab5710fb3746b0';

/// Every run mutation goes through here. A retry of the same action reuses
/// its request id, so a response lost in transit replays the stored receipt
/// instead of acting twice. Holds no subscriptions, only these flags.

abstract class _$RunActions extends $Notifier<RunActionsState> {
  RunActionsState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RunActionsState, RunActionsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RunActionsState, RunActionsState>,
              RunActionsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
