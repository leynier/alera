// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_notifications.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Unlike the board on screen, this read keeps running while the window is
/// hidden: that is exactly when a notification is useful. It only exists
/// while agent notifications are on.

@ProviderFor(runAttentionFeed)
final runAttentionFeedProvider = RunAttentionFeedProvider._();

/// Unlike the board on screen, this read keeps running while the window is
/// hidden: that is exactly when a notification is useful. It only exists
/// while agent notifications are on.

final class RunAttentionFeedProvider
    extends
        $FunctionalProvider<
          AsyncValue<RunBoardPage>,
          RunBoardPage,
          Stream<RunBoardPage>
        >
    with $FutureModifier<RunBoardPage>, $StreamProvider<RunBoardPage> {
  /// Unlike the board on screen, this read keeps running while the window is
  /// hidden: that is exactly when a notification is useful. It only exists
  /// while agent notifications are on.
  RunAttentionFeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noRetry,
        name: r'runAttentionFeedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runAttentionFeedHash();

  @$internal
  @override
  $StreamProviderElement<RunBoardPage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<RunBoardPage> create(Ref ref) {
    return runAttentionFeed(ref);
  }
}

String _$runAttentionFeedHash() => r'24560c28ae757e66561a4cf76c26bb62f3d7e002';

/// Shows "Run Needs Attention" when more runs need a decision while Activity
/// is not visible in a focused window. The body never names the run.

@ProviderFor(runAttentionNotificationCoordinator)
final runAttentionNotificationCoordinatorProvider =
    RunAttentionNotificationCoordinatorProvider._();

/// Shows "Run Needs Attention" when more runs need a decision while Activity
/// is not visible in a focused window. The body never names the run.

final class RunAttentionNotificationCoordinatorProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Shows "Run Needs Attention" when more runs need a decision while Activity
  /// is not visible in a focused window. The body never names the run.
  RunAttentionNotificationCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runAttentionNotificationCoordinatorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$runAttentionNotificationCoordinatorHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return runAttentionNotificationCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$runAttentionNotificationCoordinatorHash() =>
    r'a14f5ddb192c6c06c8671256d03eb5b38d1b7796';
