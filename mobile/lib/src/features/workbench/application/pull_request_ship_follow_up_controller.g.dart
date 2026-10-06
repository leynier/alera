// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull_request_ship_follow_up_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Last Ship follow-up chosen on this phone, remembered like the desktop Ship
/// split button.

@ProviderFor(PullRequestShipFollowUpController)
final pullRequestShipFollowUpControllerProvider =
    PullRequestShipFollowUpControllerProvider._();

/// Last Ship follow-up chosen on this phone, remembered like the desktop Ship
/// split button.
final class PullRequestShipFollowUpControllerProvider
    extends
        $AsyncNotifierProvider<
          PullRequestShipFollowUpController,
          PullRequestShipFollowUp
        > {
  /// Last Ship follow-up chosen on this phone, remembered like the desktop Ship
  /// split button.
  PullRequestShipFollowUpControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pullRequestShipFollowUpControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$pullRequestShipFollowUpControllerHash();

  @$internal
  @override
  PullRequestShipFollowUpController create() =>
      PullRequestShipFollowUpController();
}

String _$pullRequestShipFollowUpControllerHash() =>
    r'b50913bf0b5c53db4855b0956efb113eed5f8c2d';

/// Last Ship follow-up chosen on this phone, remembered like the desktop Ship
/// split button.

abstract class _$PullRequestShipFollowUpController
    extends $AsyncNotifier<PullRequestShipFollowUp> {
  FutureOr<PullRequestShipFollowUp> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<PullRequestShipFollowUp>,
              PullRequestShipFollowUp
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<PullRequestShipFollowUp>,
                PullRequestShipFollowUp
              >,
              AsyncValue<PullRequestShipFollowUp>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
