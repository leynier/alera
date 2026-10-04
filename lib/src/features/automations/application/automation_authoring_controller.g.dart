// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_authoring_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One authoring session per dialog. Validation that only the runtime can do
/// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
/// and is shown without any approval or permission step.

@ProviderFor(AutomationAuthoringController)
final automationAuthoringControllerProvider =
    AutomationAuthoringControllerFamily._();

/// One authoring session per dialog. Validation that only the runtime can do
/// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
/// and is shown without any approval or permission step.
final class AutomationAuthoringControllerProvider
    extends
        $NotifierProvider<
          AutomationAuthoringController,
          AutomationAuthoringState
        > {
  /// One authoring session per dialog. Validation that only the runtime can do
  /// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
  /// and is shown without any approval or permission step.
  AutomationAuthoringControllerProvider._({
    required AutomationAuthoringControllerFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'automationAuthoringControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$automationAuthoringControllerHash();

  @override
  String toString() {
    return r'automationAuthoringControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AutomationAuthoringController create() => AutomationAuthoringController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AutomationAuthoringState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AutomationAuthoringState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AutomationAuthoringControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$automationAuthoringControllerHash() =>
    r'9ec5016246af285ecddf7e0c2dc1cddfbf67ca30';

/// One authoring session per dialog. Validation that only the runtime can do
/// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
/// and is shown without any approval or permission step.

final class AutomationAuthoringControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AutomationAuthoringController,
          AutomationAuthoringState,
          AutomationAuthoringState,
          AutomationAuthoringState,
          int
        > {
  AutomationAuthoringControllerFamily._()
    : super(
        retry: null,
        name: r'automationAuthoringControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One authoring session per dialog. Validation that only the runtime can do
  /// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
  /// and is shown without any approval or permission step.

  AutomationAuthoringControllerProvider call(int session) =>
      AutomationAuthoringControllerProvider._(argument: session, from: this);

  @override
  String toString() => r'automationAuthoringControllerProvider';
}

/// One authoring session per dialog. Validation that only the runtime can do
/// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
/// and is shown without any approval or permission step.

abstract class _$AutomationAuthoringController
    extends $Notifier<AutomationAuthoringState> {
  late final _$args = ref.$arg as int;
  int get session => _$args;

  AutomationAuthoringState build(int session);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AutomationAuthoringState, AutomationAuthoringState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AutomationAuthoringState, AutomationAuthoringState>,
              AutomationAuthoringState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
