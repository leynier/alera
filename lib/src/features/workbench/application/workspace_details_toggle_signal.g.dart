// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_details_toggle_signal.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceDetailsToggleSignal)
final workspaceDetailsToggleSignalProvider =
    WorkspaceDetailsToggleSignalFamily._();

final class WorkspaceDetailsToggleSignalProvider
    extends $NotifierProvider<WorkspaceDetailsToggleSignal, int> {
  WorkspaceDetailsToggleSignalProvider._({
    required WorkspaceDetailsToggleSignalFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceDetailsToggleSignalProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceDetailsToggleSignalHash();

  @override
  String toString() {
    return r'workspaceDetailsToggleSignalProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspaceDetailsToggleSignal create() => WorkspaceDetailsToggleSignal();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceDetailsToggleSignalProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceDetailsToggleSignalHash() =>
    r'5754cb9348791198ce593d00f82133043b1fb71c';

final class WorkspaceDetailsToggleSignalFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceDetailsToggleSignal,
          int,
          int,
          int,
          String
        > {
  WorkspaceDetailsToggleSignalFamily._()
    : super(
        retry: null,
        name: r'workspaceDetailsToggleSignalProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceDetailsToggleSignalProvider call(String workspaceId) =>
      WorkspaceDetailsToggleSignalProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'workspaceDetailsToggleSignalProvider';
}

abstract class _$WorkspaceDetailsToggleSignal extends $Notifier<int> {
  late final _$args = ref.$arg as String;
  String get workspaceId => _$args;

  int build(String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
