// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'repository_browser_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(repositoryBrowserOpener)
final repositoryBrowserOpenerProvider = RepositoryBrowserOpenerProvider._();

final class RepositoryBrowserOpenerProvider
    extends
        $FunctionalProvider<
          RepositoryBrowserOpener,
          RepositoryBrowserOpener,
          RepositoryBrowserOpener
        >
    with $Provider<RepositoryBrowserOpener> {
  RepositoryBrowserOpenerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'repositoryBrowserOpenerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$repositoryBrowserOpenerHash();

  @$internal
  @override
  $ProviderElement<RepositoryBrowserOpener> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RepositoryBrowserOpener create(Ref ref) {
    return repositoryBrowserOpener(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RepositoryBrowserOpener value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RepositoryBrowserOpener>(value),
    );
  }
}

String _$repositoryBrowserOpenerHash() =>
    r'912bce554bddb784c8c7fdf91c434b25d8b37603';
