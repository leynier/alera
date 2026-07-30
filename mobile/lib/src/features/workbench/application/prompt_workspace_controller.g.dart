// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prompt_workspace_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PromptWorkspaceController)
final promptWorkspaceControllerProvider = PromptWorkspaceControllerFamily._();

final class PromptWorkspaceControllerProvider
    extends $NotifierProvider<PromptWorkspaceController, PromptWorkspaceState> {
  PromptWorkspaceControllerProvider._({
    required PromptWorkspaceControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'promptWorkspaceControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$promptWorkspaceControllerHash();

  @override
  String toString() {
    return r'promptWorkspaceControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PromptWorkspaceController create() => PromptWorkspaceController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PromptWorkspaceState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PromptWorkspaceState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PromptWorkspaceControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$promptWorkspaceControllerHash() =>
    r'5236c58d8c976f812b65c9f21926245d3851fcd0';

final class PromptWorkspaceControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PromptWorkspaceController,
          PromptWorkspaceState,
          PromptWorkspaceState,
          PromptWorkspaceState,
          String
        > {
  PromptWorkspaceControllerFamily._()
    : super(
        retry: null,
        name: r'promptWorkspaceControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PromptWorkspaceControllerProvider call(String hostId) =>
      PromptWorkspaceControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'promptWorkspaceControllerProvider';
}

abstract class _$PromptWorkspaceController
    extends $Notifier<PromptWorkspaceState> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  PromptWorkspaceState build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PromptWorkspaceState, PromptWorkspaceState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PromptWorkspaceState, PromptWorkspaceState>,
              PromptWorkspaceState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
