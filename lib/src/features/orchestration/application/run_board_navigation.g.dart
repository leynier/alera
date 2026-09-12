// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_board_navigation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(RunBoardNavigation)
final runBoardNavigationProvider = RunBoardNavigationProvider._();

final class RunBoardNavigationProvider
    extends $NotifierProvider<RunBoardNavigation, RunBoardLocation> {
  RunBoardNavigationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runBoardNavigationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runBoardNavigationHash();

  @$internal
  @override
  RunBoardNavigation create() => RunBoardNavigation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RunBoardLocation value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RunBoardLocation>(value),
    );
  }
}

String _$runBoardNavigationHash() =>
    r'1804649ec62f1b80035bab2586fc962746bb3036';

abstract class _$RunBoardNavigation extends $Notifier<RunBoardLocation> {
  RunBoardLocation build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RunBoardLocation, RunBoardLocation>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RunBoardLocation, RunBoardLocation>,
              RunBoardLocation,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
