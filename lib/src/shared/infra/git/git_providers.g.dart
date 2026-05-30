// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'git_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(gitBackend)
final gitBackendProvider = GitBackendProvider._();

final class GitBackendProvider
    extends $FunctionalProvider<GitBackend, GitBackend, GitBackend>
    with $Provider<GitBackend> {
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

String _$gitBackendHash() => r'9b3bfc8a8c8e46df46ef1475f6011d63a37ad482';
