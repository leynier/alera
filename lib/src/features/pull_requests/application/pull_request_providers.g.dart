// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pull_request_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(githubForgeProvider)
final githubForgeProviderProvider = GithubForgeProviderProvider._();

final class GithubForgeProviderProvider
    extends
        $FunctionalProvider<
          GitHubForgeProvider,
          GitHubForgeProvider,
          GitHubForgeProvider
        >
    with $Provider<GitHubForgeProvider> {
  GithubForgeProviderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'githubForgeProviderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$githubForgeProviderHash();

  @$internal
  @override
  $ProviderElement<GitHubForgeProvider> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  GitHubForgeProvider create(Ref ref) {
    return githubForgeProvider(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GitHubForgeProvider value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GitHubForgeProvider>(value),
    );
  }
}

String _$githubForgeProviderHash() =>
    r'a2e077efe563889196928d3126856f8f9a361172';

@ProviderFor(azureDevOpsForgeProvider)
final azureDevOpsForgeProviderProvider = AzureDevOpsForgeProviderProvider._();

final class AzureDevOpsForgeProviderProvider
    extends
        $FunctionalProvider<
          AzureDevOpsForgeProvider,
          AzureDevOpsForgeProvider,
          AzureDevOpsForgeProvider
        >
    with $Provider<AzureDevOpsForgeProvider> {
  AzureDevOpsForgeProviderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'azureDevOpsForgeProviderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$azureDevOpsForgeProviderHash();

  @$internal
  @override
  $ProviderElement<AzureDevOpsForgeProvider> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AzureDevOpsForgeProvider create(Ref ref) {
    return azureDevOpsForgeProvider(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AzureDevOpsForgeProvider value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AzureDevOpsForgeProvider>(value),
    );
  }
}

String _$azureDevOpsForgeProviderHash() =>
    r'c211fc7e2bd874cadff65fbd4097a61ee9ef6926';

@ProviderFor(forgeProviderRegistry)
final forgeProviderRegistryProvider = ForgeProviderRegistryProvider._();

final class ForgeProviderRegistryProvider
    extends
        $FunctionalProvider<
          ForgeProviderRegistry,
          ForgeProviderRegistry,
          ForgeProviderRegistry
        >
    with $Provider<ForgeProviderRegistry> {
  ForgeProviderRegistryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'forgeProviderRegistryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$forgeProviderRegistryHash();

  @$internal
  @override
  $ProviderElement<ForgeProviderRegistry> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ForgeProviderRegistry create(Ref ref) {
    return forgeProviderRegistry(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ForgeProviderRegistry value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ForgeProviderRegistry>(value),
    );
  }
}

String _$forgeProviderRegistryHash() =>
    r'54c8b4ea2edea8d1319b9efa71549b29b1b30573';

@ProviderFor(linkedReviewRepository)
final linkedReviewRepositoryProvider = LinkedReviewRepositoryProvider._();

final class LinkedReviewRepositoryProvider
    extends
        $FunctionalProvider<
          LinkedReviewRepository,
          LinkedReviewRepository,
          LinkedReviewRepository
        >
    with $Provider<LinkedReviewRepository> {
  LinkedReviewRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'linkedReviewRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$linkedReviewRepositoryHash();

  @$internal
  @override
  $ProviderElement<LinkedReviewRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LinkedReviewRepository create(Ref ref) {
    return linkedReviewRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LinkedReviewRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LinkedReviewRepository>(value),
    );
  }
}

String _$linkedReviewRepositoryHash() =>
    r'e4a5a933abb650b1e336a9db0d34c04e0049d96b';

/// The effective git-hosting-provider override for a project (UI override or
/// repo `alera.toml`), or null when the project should auto-detect. Feeds the
/// per-workspace pull-request scope.

@ProviderFor(effectiveHostingProviderOverride)
final effectiveHostingProviderOverrideProvider =
    EffectiveHostingProviderOverrideFamily._();

/// The effective git-hosting-provider override for a project (UI override or
/// repo `alera.toml`), or null when the project should auto-detect. Feeds the
/// per-workspace pull-request scope.

final class EffectiveHostingProviderOverrideProvider
    extends
        $FunctionalProvider<
          AsyncValue<GitHostingProvider?>,
          GitHostingProvider?,
          FutureOr<GitHostingProvider?>
        >
    with
        $FutureModifier<GitHostingProvider?>,
        $FutureProvider<GitHostingProvider?> {
  /// The effective git-hosting-provider override for a project (UI override or
  /// repo `alera.toml`), or null when the project should auto-detect. Feeds the
  /// per-workspace pull-request scope.
  EffectiveHostingProviderOverrideProvider._({
    required EffectiveHostingProviderOverrideFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'effectiveHostingProviderOverrideProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$effectiveHostingProviderOverrideHash();

  @override
  String toString() {
    return r'effectiveHostingProviderOverrideProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<GitHostingProvider?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<GitHostingProvider?> create(Ref ref) {
    final argument = this.argument as String;
    return effectiveHostingProviderOverride(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is EffectiveHostingProviderOverrideProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$effectiveHostingProviderOverrideHash() =>
    r'4a1e0c5d0a466146e45d4df86d2185edc0ef9011';

/// The effective git-hosting-provider override for a project (UI override or
/// repo `alera.toml`), or null when the project should auto-detect. Feeds the
/// per-workspace pull-request scope.

final class EffectiveHostingProviderOverrideFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<GitHostingProvider?>, String> {
  EffectiveHostingProviderOverrideFamily._()
    : super(
        retry: null,
        name: r'effectiveHostingProviderOverrideProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The effective git-hosting-provider override for a project (UI override or
  /// repo `alera.toml`), or null when the project should auto-detect. Feeds the
  /// per-workspace pull-request scope.

  EffectiveHostingProviderOverrideProvider call(String projectId) =>
      EffectiveHostingProviderOverrideProvider._(
        argument: projectId,
        from: this,
      );

  @override
  String toString() => r'effectiveHostingProviderOverrideProvider';
}
