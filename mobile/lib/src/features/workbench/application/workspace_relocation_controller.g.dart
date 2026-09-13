// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_relocation_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceRelocationController)
final workspaceRelocationControllerProvider =
    WorkspaceRelocationControllerFamily._();

final class WorkspaceRelocationControllerProvider
    extends
        $NotifierProvider<
          WorkspaceRelocationController,
          WorkspaceRelocationForm
        > {
  WorkspaceRelocationControllerProvider._({
    required WorkspaceRelocationControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'workspaceRelocationControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceRelocationControllerHash();

  @override
  String toString() {
    return r'workspaceRelocationControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  WorkspaceRelocationController create() => WorkspaceRelocationController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceRelocationForm value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceRelocationForm>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceRelocationControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceRelocationControllerHash() =>
    r'58f4eb99a201a782ea93c7c20835811d437c0df8';

final class WorkspaceRelocationControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceRelocationController,
          WorkspaceRelocationForm,
          WorkspaceRelocationForm,
          WorkspaceRelocationForm,
          (String, String)
        > {
  WorkspaceRelocationControllerFamily._()
    : super(
        retry: null,
        name: r'workspaceRelocationControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceRelocationControllerProvider call(
    String hostId,
    String workspaceId,
  ) => WorkspaceRelocationControllerProvider._(
    argument: (hostId, workspaceId),
    from: this,
  );

  @override
  String toString() => r'workspaceRelocationControllerProvider';
}

abstract class _$WorkspaceRelocationController
    extends $Notifier<WorkspaceRelocationForm> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  WorkspaceRelocationForm build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<WorkspaceRelocationForm, WorkspaceRelocationForm>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WorkspaceRelocationForm, WorkspaceRelocationForm>,
              WorkspaceRelocationForm,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
