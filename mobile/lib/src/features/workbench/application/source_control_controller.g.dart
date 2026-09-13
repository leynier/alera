// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_control_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SourceControlController)
final sourceControlControllerProvider = SourceControlControllerFamily._();

final class SourceControlControllerProvider
    extends
        $AsyncNotifierProvider<
          SourceControlController,
          MobileGitStatusSnapshot
        > {
  SourceControlControllerProvider._({
    required SourceControlControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'sourceControlControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sourceControlControllerHash();

  @override
  String toString() {
    return r'sourceControlControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SourceControlController create() => SourceControlController();

  @override
  bool operator ==(Object other) {
    return other is SourceControlControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sourceControlControllerHash() =>
    r'7677cc2ee21b154af9fe9ad87ca06134931b3982';

final class SourceControlControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SourceControlController,
          AsyncValue<MobileGitStatusSnapshot>,
          MobileGitStatusSnapshot,
          FutureOr<MobileGitStatusSnapshot>,
          (String, String)
        > {
  SourceControlControllerFamily._()
    : super(
        retry: null,
        name: r'sourceControlControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SourceControlControllerProvider call(String hostId, String workspaceId) =>
      SourceControlControllerProvider._(
        argument: (hostId, workspaceId),
        from: this,
      );

  @override
  String toString() => r'sourceControlControllerProvider';
}

abstract class _$SourceControlController
    extends $AsyncNotifier<MobileGitStatusSnapshot> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  FutureOr<MobileGitStatusSnapshot> build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<MobileGitStatusSnapshot>,
              MobileGitStatusSnapshot
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<MobileGitStatusSnapshot>,
                MobileGitStatusSnapshot
              >,
              AsyncValue<MobileGitStatusSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
