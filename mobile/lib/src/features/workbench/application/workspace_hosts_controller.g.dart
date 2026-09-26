// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_hosts_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The hosts that own workspaces on one paired runtime, refreshed on
/// `sshTargetsChanged`. A failed load keeps the last directory, and a first
/// load that fails still marks remote workspaces under their raw host id.

@ProviderFor(WorkspaceHostsController)
final workspaceHostsControllerProvider = WorkspaceHostsControllerFamily._();

/// The hosts that own workspaces on one paired runtime, refreshed on
/// `sshTargetsChanged`. A failed load keeps the last directory, and a first
/// load that fails still marks remote workspaces under their raw host id.
final class WorkspaceHostsControllerProvider
    extends
        $AsyncNotifierProvider<
          WorkspaceHostsController,
          MobileWorkspaceHostDirectory
        > {
  /// The hosts that own workspaces on one paired runtime, refreshed on
  /// `sshTargetsChanged`. A failed load keeps the last directory, and a first
  /// load that fails still marks remote workspaces under their raw host id.
  WorkspaceHostsControllerProvider._({
    required WorkspaceHostsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceHostsControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceHostsControllerHash();

  @override
  String toString() {
    return r'workspaceHostsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspaceHostsController create() => WorkspaceHostsController();

  @override
  bool operator ==(Object other) {
    return other is WorkspaceHostsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceHostsControllerHash() =>
    r'68b71c57c46823d35f0d01e3a52b0324a549a8fb';

/// The hosts that own workspaces on one paired runtime, refreshed on
/// `sshTargetsChanged`. A failed load keeps the last directory, and a first
/// load that fails still marks remote workspaces under their raw host id.

final class WorkspaceHostsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceHostsController,
          AsyncValue<MobileWorkspaceHostDirectory>,
          MobileWorkspaceHostDirectory,
          FutureOr<MobileWorkspaceHostDirectory>,
          String
        > {
  WorkspaceHostsControllerFamily._()
    : super(
        retry: null,
        name: r'workspaceHostsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The hosts that own workspaces on one paired runtime, refreshed on
  /// `sshTargetsChanged`. A failed load keeps the last directory, and a first
  /// load that fails still marks remote workspaces under their raw host id.

  WorkspaceHostsControllerProvider call(String hostId) =>
      WorkspaceHostsControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'workspaceHostsControllerProvider';
}

/// The hosts that own workspaces on one paired runtime, refreshed on
/// `sshTargetsChanged`. A failed load keeps the last directory, and a first
/// load that fails still marks remote workspaces under their raw host id.

abstract class _$WorkspaceHostsController
    extends $AsyncNotifier<MobileWorkspaceHostDirectory> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<MobileWorkspaceHostDirectory> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<MobileWorkspaceHostDirectory>,
              MobileWorkspaceHostDirectory
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<MobileWorkspaceHostDirectory>,
                MobileWorkspaceHostDirectory
              >,
              AsyncValue<MobileWorkspaceHostDirectory>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
