// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_timeline_page.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The newest page is watched; older pages are appended on demand. Entries
/// never change once written, so a refreshed newest page merges with the
/// older pages already loaded instead of dropping them.

@ProviderFor(RunTimeline)
final runTimelineProvider = RunTimelineFamily._();

/// The newest page is watched; older pages are appended on demand. Entries
/// never change once written, so a refreshed newest page merges with the
/// older pages already loaded instead of dropping them.
final class RunTimelineProvider
    extends $StreamNotifierProvider<RunTimeline, RunPageRead<RunTimelineView>> {
  /// The newest page is watched; older pages are appended on demand. Entries
  /// never change once written, so a refreshed newest page merges with the
  /// older pages already loaded instead of dropping them.
  RunTimelineProvider._({
    required RunTimelineFamily super.from,
    required (String, RunTimelineFilter) super.argument,
  }) : super(
         retry: runNoRetry,
         name: r'runTimelineProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$runTimelineHash();

  @override
  String toString() {
    return r'runTimelineProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  RunTimeline create() => RunTimeline();

  @override
  bool operator ==(Object other) {
    return other is RunTimelineProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$runTimelineHash() => r'4a26ebb907e63be55ea7e75a8e129fab6c5dd4c1';

/// The newest page is watched; older pages are appended on demand. Entries
/// never change once written, so a refreshed newest page merges with the
/// older pages already loaded instead of dropping them.

final class RunTimelineFamily extends $Family
    with
        $ClassFamilyOverride<
          RunTimeline,
          AsyncValue<RunPageRead<RunTimelineView>>,
          RunPageRead<RunTimelineView>,
          Stream<RunPageRead<RunTimelineView>>,
          (String, RunTimelineFilter)
        > {
  RunTimelineFamily._()
    : super(
        retry: runNoRetry,
        name: r'runTimelineProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The newest page is watched; older pages are appended on demand. Entries
  /// never change once written, so a refreshed newest page merges with the
  /// older pages already loaded instead of dropping them.

  RunTimelineProvider call(String runId, RunTimelineFilter filter) =>
      RunTimelineProvider._(argument: (runId, filter), from: this);

  @override
  String toString() => r'runTimelineProvider';
}

/// The newest page is watched; older pages are appended on demand. Entries
/// never change once written, so a refreshed newest page merges with the
/// older pages already loaded instead of dropping them.

abstract class _$RunTimeline
    extends $StreamNotifier<RunPageRead<RunTimelineView>> {
  late final _$args = ref.$arg as (String, RunTimelineFilter);
  String get runId => _$args.$1;
  RunTimelineFilter get filter => _$args.$2;

  Stream<RunPageRead<RunTimelineView>> build(
    String runId,
    RunTimelineFilter filter,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<RunPageRead<RunTimelineView>>,
              RunPageRead<RunTimelineView>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<RunPageRead<RunTimelineView>>,
                RunPageRead<RunTimelineView>
              >,
              AsyncValue<RunPageRead<RunTimelineView>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
