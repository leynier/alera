// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull_request_action_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the paired runtime accepts `mobile.pullRequest.*` writes. False on
/// an older runtime, which keeps the panel read-only.

@ProviderFor(pullRequestActionsSupported)
final pullRequestActionsSupportedProvider =
    PullRequestActionsSupportedFamily._();

/// Whether the paired runtime accepts `mobile.pullRequest.*` writes. False on
/// an older runtime, which keeps the panel read-only.

final class PullRequestActionsSupportedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the paired runtime accepts `mobile.pullRequest.*` writes. False on
  /// an older runtime, which keeps the panel read-only.
  PullRequestActionsSupportedProvider._({
    required PullRequestActionsSupportedFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'pullRequestActionsSupportedProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pullRequestActionsSupportedHash();

  @override
  String toString() {
    return r'pullRequestActionsSupportedProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as String;
    return pullRequestActionsSupported(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PullRequestActionsSupportedProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pullRequestActionsSupportedHash() =>
    r'88543382c4b1999cfd5886be62f7d3c8e5b2da8d';

/// Whether the paired runtime accepts `mobile.pullRequest.*` writes. False on
/// an older runtime, which keeps the panel read-only.

final class PullRequestActionsSupportedFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  PullRequestActionsSupportedFamily._()
    : super(
        retry: null,
        name: r'pullRequestActionsSupportedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the paired runtime accepts `mobile.pullRequest.*` writes. False on
  /// an older runtime, which keeps the panel read-only.

  PullRequestActionsSupportedProvider call(String hostId) =>
      PullRequestActionsSupportedProvider._(argument: hostId, from: this);

  @override
  String toString() => r'pullRequestActionsSupportedProvider';
}

/// The pull request write in flight for one workspace, or null when idle.
///
/// Kept alive so a merge started just before the user leaves the panel still
/// lands its snapshot and still reports a failure: the panel and its sheets
/// can be disposed while GitHub answers.

@ProviderFor(PullRequestActionController)
final pullRequestActionControllerProvider =
    PullRequestActionControllerFamily._();

/// The pull request write in flight for one workspace, or null when idle.
///
/// Kept alive so a merge started just before the user leaves the panel still
/// lands its snapshot and still reports a failure: the panel and its sheets
/// can be disposed while GitHub answers.
final class PullRequestActionControllerProvider
    extends
        $NotifierProvider<PullRequestActionController, PullRequestActionKind?> {
  /// The pull request write in flight for one workspace, or null when idle.
  ///
  /// Kept alive so a merge started just before the user leaves the panel still
  /// lands its snapshot and still reports a failure: the panel and its sheets
  /// can be disposed while GitHub answers.
  PullRequestActionControllerProvider._({
    required PullRequestActionControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'pullRequestActionControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pullRequestActionControllerHash();

  @override
  String toString() {
    return r'pullRequestActionControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  PullRequestActionController create() => PullRequestActionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PullRequestActionKind? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PullRequestActionKind?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PullRequestActionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pullRequestActionControllerHash() =>
    r'740acf17ed0460fcdfc242511d484acd0a3fe52b';

/// The pull request write in flight for one workspace, or null when idle.
///
/// Kept alive so a merge started just before the user leaves the panel still
/// lands its snapshot and still reports a failure: the panel and its sheets
/// can be disposed while GitHub answers.

final class PullRequestActionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PullRequestActionController,
          PullRequestActionKind?,
          PullRequestActionKind?,
          PullRequestActionKind?,
          (String, String)
        > {
  PullRequestActionControllerFamily._()
    : super(
        retry: null,
        name: r'pullRequestActionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The pull request write in flight for one workspace, or null when idle.
  ///
  /// Kept alive so a merge started just before the user leaves the panel still
  /// lands its snapshot and still reports a failure: the panel and its sheets
  /// can be disposed while GitHub answers.

  PullRequestActionControllerProvider call(String hostId, String workspaceId) =>
      PullRequestActionControllerProvider._(
        argument: (hostId, workspaceId),
        from: this,
      );

  @override
  String toString() => r'pullRequestActionControllerProvider';
}

/// The pull request write in flight for one workspace, or null when idle.
///
/// Kept alive so a merge started just before the user leaves the panel still
/// lands its snapshot and still reports a failure: the panel and its sheets
/// can be disposed while GitHub answers.

abstract class _$PullRequestActionController
    extends $Notifier<PullRequestActionKind?> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  PullRequestActionKind? build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<PullRequestActionKind?, PullRequestActionKind?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PullRequestActionKind?, PullRequestActionKind?>,
              PullRequestActionKind?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
