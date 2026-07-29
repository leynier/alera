// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_update_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mobileReleaseSource)
final mobileReleaseSourceProvider = MobileReleaseSourceProvider._();

final class MobileReleaseSourceProvider
    extends
        $FunctionalProvider<
          GitHubMobileReleaseSource,
          GitHubMobileReleaseSource,
          GitHubMobileReleaseSource
        >
    with $Provider<GitHubMobileReleaseSource> {
  MobileReleaseSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileReleaseSourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileReleaseSourceHash();

  @$internal
  @override
  $ProviderElement<GitHubMobileReleaseSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  GitHubMobileReleaseSource create(Ref ref) {
    return mobileReleaseSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GitHubMobileReleaseSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GitHubMobileReleaseSource>(value),
    );
  }
}

String _$mobileReleaseSourceHash() =>
    r'ef00afd43178bd293972085937220e94533e8ad4';

/// The newest release worth offering, or null when the app is current.
///
/// This resolves once per launch: it is `keepAlive`, so returning to a screen
/// that watches it does not spend another GitHub API call.

@ProviderFor(availableMobileUpdate)
final availableMobileUpdateProvider = AvailableMobileUpdateProvider._();

/// The newest release worth offering, or null when the app is current.
///
/// This resolves once per launch: it is `keepAlive`, so returning to a screen
/// that watches it does not spend another GitHub API call.

final class AvailableMobileUpdateProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileRelease?>,
          MobileRelease?,
          FutureOr<MobileRelease?>
        >
    with $FutureModifier<MobileRelease?>, $FutureProvider<MobileRelease?> {
  /// The newest release worth offering, or null when the app is current.
  ///
  /// This resolves once per launch: it is `keepAlive`, so returning to a screen
  /// that watches it does not spend another GitHub API call.
  AvailableMobileUpdateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'availableMobileUpdateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$availableMobileUpdateHash();

  @$internal
  @override
  $FutureProviderElement<MobileRelease?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileRelease?> create(Ref ref) {
    return availableMobileUpdate(ref);
  }
}

String _$availableMobileUpdateHash() =>
    r'b89831100cffd6773f5981253d90071e9c347e08';
