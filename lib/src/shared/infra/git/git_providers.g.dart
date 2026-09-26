// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'git_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The one [GitBackend] the app reads. Paths inside a remote workspace go to
/// that host's runtime backend, everything else to the local bridge, so a
/// caller never has to know where a checkout lives.
///
/// The workbench state is read lazily on each call rather than watched: this
/// provider is a build-time dependency of the services the controller itself
/// uses, and watching it here would close that loop.

@ProviderFor(gitBackend)
final gitBackendProvider = GitBackendProvider._();

/// The one [GitBackend] the app reads. Paths inside a remote workspace go to
/// that host's runtime backend, everything else to the local bridge, so a
/// caller never has to know where a checkout lives.
///
/// The workbench state is read lazily on each call rather than watched: this
/// provider is a build-time dependency of the services the controller itself
/// uses, and watching it here would close that loop.

final class GitBackendProvider
    extends $FunctionalProvider<GitBackend, GitBackend, GitBackend>
    with $Provider<GitBackend> {
  /// The one [GitBackend] the app reads. Paths inside a remote workspace go to
  /// that host's runtime backend, everything else to the local bridge, so a
  /// caller never has to know where a checkout lives.
  ///
  /// The workbench state is read lazily on each call rather than watched: this
  /// provider is a build-time dependency of the services the controller itself
  /// uses, and watching it here would close that loop.
  GitBackendProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gitBackendProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gitBackendHash();

  @$internal
  @override
  $ProviderElement<GitBackend> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GitBackend create(Ref ref) {
    return gitBackend(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GitBackend value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GitBackend>(value),
    );
  }
}

String _$gitBackendHash() => r'ababd57b0c5d82cca54302be31df68d7944028a9';

/// Reads the workbench state lazily, for the reason given on [gitBackend], and
/// rebuilds the index only when that state object changes.

@ProviderFor(remoteWorkspacePathResolver)
final remoteWorkspacePathResolverProvider =
    RemoteWorkspacePathResolverProvider._();

/// Reads the workbench state lazily, for the reason given on [gitBackend], and
/// rebuilds the index only when that state object changes.

final class RemoteWorkspacePathResolverProvider
    extends
        $FunctionalProvider<
          RemoteWorkspacePathResolver,
          RemoteWorkspacePathResolver,
          RemoteWorkspacePathResolver
        >
    with $Provider<RemoteWorkspacePathResolver> {
  /// Reads the workbench state lazily, for the reason given on [gitBackend], and
  /// rebuilds the index only when that state object changes.
  RemoteWorkspacePathResolverProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'remoteWorkspacePathResolverProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$remoteWorkspacePathResolverHash();

  @$internal
  @override
  $ProviderElement<RemoteWorkspacePathResolver> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RemoteWorkspacePathResolver create(Ref ref) {
    return remoteWorkspacePathResolver(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RemoteWorkspacePathResolver value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RemoteWorkspacePathResolver>(value),
    );
  }
}

String _$remoteWorkspacePathResolverHash() =>
    r'e440eef4dd7bcf4179a517f489b2effe34ea2a38';
