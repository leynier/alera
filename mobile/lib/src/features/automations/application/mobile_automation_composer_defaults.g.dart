// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_automation_composer_defaults.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The agent profile the last saved automation on [hostId] used while the
/// app runs, so the next one starts with it.

@ProviderFor(MobileAutomationLastAgentProfile)
final mobileAutomationLastAgentProfileProvider =
    MobileAutomationLastAgentProfileFamily._();

/// The agent profile the last saved automation on [hostId] used while the
/// app runs, so the next one starts with it.
final class MobileAutomationLastAgentProfileProvider
    extends $NotifierProvider<MobileAutomationLastAgentProfile, String?> {
  /// The agent profile the last saved automation on [hostId] used while the
  /// app runs, so the next one starts with it.
  MobileAutomationLastAgentProfileProvider._({
    required MobileAutomationLastAgentProfileFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationLastAgentProfileProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationLastAgentProfileHash();

  @override
  String toString() {
    return r'mobileAutomationLastAgentProfileProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileAutomationLastAgentProfile create() =>
      MobileAutomationLastAgentProfile();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationLastAgentProfileProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationLastAgentProfileHash() =>
    r'cf9a67bfd32c1a2e2eb640e3f73c635048bc761e';

/// The agent profile the last saved automation on [hostId] used while the
/// app runs, so the next one starts with it.

final class MobileAutomationLastAgentProfileFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAutomationLastAgentProfile,
          String?,
          String?,
          String?,
          String
        > {
  MobileAutomationLastAgentProfileFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationLastAgentProfileProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The agent profile the last saved automation on [hostId] used while the
  /// app runs, so the next one starts with it.

  MobileAutomationLastAgentProfileProvider call(String hostId) =>
      MobileAutomationLastAgentProfileProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationLastAgentProfileProvider';
}

/// The agent profile the last saved automation on [hostId] used while the
/// app runs, so the next one starts with it.

abstract class _$MobileAutomationLastAgentProfile extends $Notifier<String?> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  String? build(String hostId);
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
    return element.handleCreate(ref, () => build(_$args));
  }
}
