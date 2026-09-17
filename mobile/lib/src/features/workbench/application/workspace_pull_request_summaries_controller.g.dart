// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_pull_request_summaries_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every workspace row indicator on one host. Refreshed when the runtime
/// reports topology or link changes; a transient failure keeps the last
/// snapshot so the rows do not blink empty between polls.

@ProviderFor(WorkspacePullRequestSummariesController)
final workspacePullRequestSummariesControllerProvider =
    WorkspacePullRequestSummariesControllerFamily._();

/// Every workspace row indicator on one host. Refreshed when the runtime
/// reports topology or link changes; a transient failure keeps the last
/// snapshot so the rows do not blink empty between polls.
final class WorkspacePullRequestSummariesControllerProvider
    extends
        $AsyncNotifierProvider<
          WorkspacePullRequestSummariesController,
          Map<String, MobileWorkspacePullRequestSummary>
        > {
  /// Every workspace row indicator on one host. Refreshed when the runtime
  /// reports topology or link changes; a transient failure keeps the last
  /// snapshot so the rows do not blink empty between polls.
  WorkspacePullRequestSummariesControllerProvider._({
    required WorkspacePullRequestSummariesControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspacePullRequestSummariesControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$workspacePullRequestSummariesControllerHash();

  @override
  String toString() {
    return r'workspacePullRequestSummariesControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspacePullRequestSummariesController create() =>
      WorkspacePullRequestSummariesController();

  @override
  bool operator ==(Object other) {
    return other is WorkspacePullRequestSummariesControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspacePullRequestSummariesControllerHash() =>
    r'475e8314446cb97608de5e5e9687dd87c4ffac51';

/// Every workspace row indicator on one host. Refreshed when the runtime
/// reports topology or link changes; a transient failure keeps the last
/// snapshot so the rows do not blink empty between polls.

final class WorkspacePullRequestSummariesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspacePullRequestSummariesController,
          AsyncValue<Map<String, MobileWorkspacePullRequestSummary>>,
          Map<String, MobileWorkspacePullRequestSummary>,
          FutureOr<Map<String, MobileWorkspacePullRequestSummary>>,
          String
        > {
  WorkspacePullRequestSummariesControllerFamily._()
    : super(
        retry: null,
        name: r'workspacePullRequestSummariesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every workspace row indicator on one host. Refreshed when the runtime
  /// reports topology or link changes; a transient failure keeps the last
  /// snapshot so the rows do not blink empty between polls.

  WorkspacePullRequestSummariesControllerProvider call(String hostId) =>
      WorkspacePullRequestSummariesControllerProvider._(
        argument: hostId,
        from: this,
      );

  @override
  String toString() => r'workspacePullRequestSummariesControllerProvider';
}

/// Every workspace row indicator on one host. Refreshed when the runtime
/// reports topology or link changes; a transient failure keeps the last
/// snapshot so the rows do not blink empty between polls.

abstract class _$WorkspacePullRequestSummariesController
    extends $AsyncNotifier<Map<String, MobileWorkspacePullRequestSummary>> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<Map<String, MobileWorkspacePullRequestSummary>> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<Map<String, MobileWorkspacePullRequestSummary>>,
              Map<String, MobileWorkspacePullRequestSummary>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<Map<String, MobileWorkspacePullRequestSummary>>,
                Map<String, MobileWorkspacePullRequestSummary>
              >,
              AsyncValue<Map<String, MobileWorkspacePullRequestSummary>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
