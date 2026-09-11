// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'background_setup_jobs.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BackgroundSetupJobs)
final backgroundSetupJobsProvider = BackgroundSetupJobsProvider._();

final class BackgroundSetupJobsProvider
    extends $NotifierProvider<BackgroundSetupJobs, BackgroundSetupJobsState> {
  BackgroundSetupJobsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backgroundSetupJobsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backgroundSetupJobsHash();

  @$internal
  @override
  BackgroundSetupJobs create() => BackgroundSetupJobs();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackgroundSetupJobsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackgroundSetupJobsState>(value),
    );
  }
}

String _$backgroundSetupJobsHash() =>
    r'873ef570111a27a140d82324d0b10243f36e1f44';

abstract class _$BackgroundSetupJobs
    extends $Notifier<BackgroundSetupJobsState> {
  BackgroundSetupJobsState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<BackgroundSetupJobsState, BackgroundSetupJobsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BackgroundSetupJobsState, BackgroundSetupJobsState>,
              BackgroundSetupJobsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
