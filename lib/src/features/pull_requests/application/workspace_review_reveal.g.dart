// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_review_reveal.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceReviewReveal)
final workspaceReviewRevealProvider = WorkspaceReviewRevealFamily._();

final class WorkspaceReviewRevealProvider
    extends $NotifierProvider<WorkspaceReviewReveal, int?> {
  WorkspaceReviewRevealProvider._({
    required WorkspaceReviewRevealFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceReviewRevealProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceReviewRevealHash();

  @override
  String toString() {
    return r'workspaceReviewRevealProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspaceReviewReveal create() => WorkspaceReviewReveal();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceReviewRevealProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceReviewRevealHash() =>
    r'26f9e7550c836216882a74637244539851c5b536';

final class WorkspaceReviewRevealFamily extends $Family
    with $ClassFamilyOverride<WorkspaceReviewReveal, int?, int?, int?, String> {
  WorkspaceReviewRevealFamily._()
    : super(
        retry: null,
        name: r'workspaceReviewRevealProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  WorkspaceReviewRevealProvider call(String workspaceId) =>
      WorkspaceReviewRevealProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'workspaceReviewRevealProvider';
}

abstract class _$WorkspaceReviewReveal extends $Notifier<int?> {
  late final _$args = ref.$arg as String;
  String get workspaceId => _$args;

  int? build(String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int?, int?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int?, int?>,
              int?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
