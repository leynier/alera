// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_search_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceSearchController)
final workspaceSearchControllerProvider = WorkspaceSearchControllerFamily._();

final class WorkspaceSearchControllerProvider
    extends $NotifierProvider<WorkspaceSearchController, String> {
  WorkspaceSearchControllerProvider._({
    required WorkspaceSearchControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceSearchControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceSearchControllerHash();

  @override
  String toString() {
    return r'workspaceSearchControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspaceSearchController create() => WorkspaceSearchController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceSearchControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceSearchControllerHash() =>
    r'5cbf657f40990ad8876179251bc01d0f889f8149';

final class WorkspaceSearchControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceSearchController,
          String,
          String,
          String,
          String
        > {
  WorkspaceSearchControllerFamily._()
    : super(
        retry: null,
        name: r'workspaceSearchControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceSearchControllerProvider call(String hostId) =>
      WorkspaceSearchControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'workspaceSearchControllerProvider';
}

abstract class _$WorkspaceSearchController extends $Notifier<String> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  String build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
