// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'github_star_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(GitHubStarController)
final gitHubStarControllerProvider = GitHubStarControllerProvider._();

final class GitHubStarControllerProvider
    extends $NotifierProvider<GitHubStarController, GitHubStarState> {
  GitHubStarControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gitHubStarControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gitHubStarControllerHash();

  @$internal
  @override
  GitHubStarController create() => GitHubStarController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GitHubStarState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GitHubStarState>(value),
    );
  }
}

String _$gitHubStarControllerHash() =>
    r'7b4e1234db2127c379441930a6fa06a33abe8c61';

abstract class _$GitHubStarController extends $Notifier<GitHubStarState> {
  GitHubStarState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<GitHubStarState, GitHubStarState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<GitHubStarState, GitHubStarState>,
              GitHubStarState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
