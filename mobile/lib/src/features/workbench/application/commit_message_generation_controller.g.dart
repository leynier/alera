// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'commit_message_generation_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Generates a commit message on the runtime for one workspace. The state is
/// the operation id of the run in flight, which is also what cancels it.

@ProviderFor(CommitMessageGenerationController)
final commitMessageGenerationControllerProvider =
    CommitMessageGenerationControllerFamily._();

/// Generates a commit message on the runtime for one workspace. The state is
/// the operation id of the run in flight, which is also what cancels it.
final class CommitMessageGenerationControllerProvider
    extends $NotifierProvider<CommitMessageGenerationController, String?> {
  /// Generates a commit message on the runtime for one workspace. The state is
  /// the operation id of the run in flight, which is also what cancels it.
  CommitMessageGenerationControllerProvider._({
    required CommitMessageGenerationControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'commitMessageGenerationControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$commitMessageGenerationControllerHash();

  @override
  String toString() {
    return r'commitMessageGenerationControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  CommitMessageGenerationController create() =>
      CommitMessageGenerationController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CommitMessageGenerationControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$commitMessageGenerationControllerHash() =>
    r'ad45e2bdc8786615e1d0c9a682cc209ed62b1707';

/// Generates a commit message on the runtime for one workspace. The state is
/// the operation id of the run in flight, which is also what cancels it.

final class CommitMessageGenerationControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          CommitMessageGenerationController,
          String?,
          String?,
          String?,
          (String, String)
        > {
  CommitMessageGenerationControllerFamily._()
    : super(
        retry: null,
        name: r'commitMessageGenerationControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Generates a commit message on the runtime for one workspace. The state is
  /// the operation id of the run in flight, which is also what cancels it.

  CommitMessageGenerationControllerProvider call(
    String hostId,
    String workspaceId,
  ) => CommitMessageGenerationControllerProvider._(
    argument: (hostId, workspaceId),
    from: this,
  );

  @override
  String toString() => r'commitMessageGenerationControllerProvider';
}

/// Generates a commit message on the runtime for one workspace. The state is
/// the operation id of the run in flight, which is also what cancels it.

abstract class _$CommitMessageGenerationController extends $Notifier<String?> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  String? build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
