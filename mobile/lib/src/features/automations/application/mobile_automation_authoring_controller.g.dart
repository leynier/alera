// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_automation_authoring_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One authoring session per dialog. Validation that only the runtime can do
/// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
/// and is shown without any approval or permission step.

@ProviderFor(MobileAutomationAuthoringController)
final mobileAutomationAuthoringControllerProvider =
    MobileAutomationAuthoringControllerFamily._();

/// One authoring session per dialog. Validation that only the runtime can do
/// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
/// and is shown without any approval or permission step.
final class MobileAutomationAuthoringControllerProvider
    extends
        $NotifierProvider<
          MobileAutomationAuthoringController,
          AutomationAuthoringState
        > {
  /// One authoring session per dialog. Validation that only the runtime can do
  /// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
  /// and is shown without any approval or permission step.
  MobileAutomationAuthoringControllerProvider._({
    required MobileAutomationAuthoringControllerFamily super.from,
    required (String, int) super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationAuthoringControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$mobileAutomationAuthoringControllerHash();

  @override
  String toString() {
    return r'mobileAutomationAuthoringControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileAutomationAuthoringController create() =>
      MobileAutomationAuthoringController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AutomationAuthoringState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AutomationAuthoringState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationAuthoringControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationAuthoringControllerHash() =>
    r'5aeda56ae4d645078b17c0d3bd80098b7440b907';

/// One authoring session per dialog. Validation that only the runtime can do
/// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
/// and is shown without any approval or permission step.

final class MobileAutomationAuthoringControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAutomationAuthoringController,
          AutomationAuthoringState,
          AutomationAuthoringState,
          AutomationAuthoringState,
          (String, int)
        > {
  MobileAutomationAuthoringControllerFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationAuthoringControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One authoring session per dialog. Validation that only the runtime can do
  /// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
  /// and is shown without any approval or permission step.

  MobileAutomationAuthoringControllerProvider call(
    String hostId,
    int session,
  ) => MobileAutomationAuthoringControllerProvider._(
    argument: (hostId, session),
    from: this,
  );

  @override
  String toString() => r'mobileAutomationAuthoringControllerProvider';
}

/// One authoring session per dialog. Validation that only the runtime can do
/// (targets, profiles, hosts, CLIs) comes back through `automation.readiness`
/// and is shown without any approval or permission step.

abstract class _$MobileAutomationAuthoringController
    extends $Notifier<AutomationAuthoringState> {
  late final _$args = ref.$arg as (String, int);
  String get hostId => _$args.$1;
  int get session => _$args.$2;

  AutomationAuthoringState build(String hostId, int session);
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
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
