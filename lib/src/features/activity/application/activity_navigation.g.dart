// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_navigation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Where the Activity page is. Nothing here selects a workspace: Open
/// Workspace and Open Terminal are explicit actions that close the page.
// Retain only navigation, never runtime snapshots or subscriptions.

@ProviderFor(ActivityNavigation)
final activityNavigationProvider = ActivityNavigationProvider._();

/// Where the Activity page is. Nothing here selects a workspace: Open
/// Workspace and Open Terminal are explicit actions that close the page.
// Retain only navigation, never runtime snapshots or subscriptions.
final class ActivityNavigationProvider
    extends $NotifierProvider<ActivityNavigation, ActivityLocation> {
  /// Where the Activity page is. Nothing here selects a workspace: Open
  /// Workspace and Open Terminal are explicit actions that close the page.
  // Retain only navigation, never runtime snapshots or subscriptions.
  ActivityNavigationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activityNavigationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activityNavigationHash();

  @$internal
  @override
  ActivityNavigation create() => ActivityNavigation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActivityLocation value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActivityLocation>(value),
    );
  }
}

String _$activityNavigationHash() =>
    r'53021bd231e2a82a1b8f2e945fca0ba4d048ab3b';

/// Where the Activity page is. Nothing here selects a workspace: Open
/// Workspace and Open Terminal are explicit actions that close the page.
// Retain only navigation, never runtime snapshots or subscriptions.

abstract class _$ActivityNavigation extends $Notifier<ActivityLocation> {
  ActivityLocation build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ActivityLocation, ActivityLocation>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ActivityLocation, ActivityLocation>,
              ActivityLocation,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
