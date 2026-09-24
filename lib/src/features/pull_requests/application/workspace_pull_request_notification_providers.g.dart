// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_pull_request_notification_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workspacePullRequestFailureNotificationCoordinator)
final workspacePullRequestFailureNotificationCoordinatorProvider =
    WorkspacePullRequestFailureNotificationCoordinatorProvider._();

final class WorkspacePullRequestFailureNotificationCoordinatorProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  WorkspacePullRequestFailureNotificationCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspacePullRequestFailureNotificationCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$workspacePullRequestFailureNotificationCoordinatorHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return workspacePullRequestFailureNotificationCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$workspacePullRequestFailureNotificationCoordinatorHash() =>
    r'a9bae8698a010684d8ae1202e76bbc80b9e49f79';
