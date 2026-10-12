// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_composer_defaults.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The agent profile the last saved automation used in this session, so the
/// next one starts with it.

@ProviderFor(AutomationLastAgentProfile)
final automationLastAgentProfileProvider =
    AutomationLastAgentProfileProvider._();

/// The agent profile the last saved automation used in this session, so the
/// next one starts with it.
final class AutomationLastAgentProfileProvider
    extends $NotifierProvider<AutomationLastAgentProfile, String?> {
  /// The agent profile the last saved automation used in this session, so the
  /// next one starts with it.
  AutomationLastAgentProfileProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationLastAgentProfileProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationLastAgentProfileHash();

  @$internal
  @override
  AutomationLastAgentProfile create() => AutomationLastAgentProfile();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$automationLastAgentProfileHash() =>
    r'964274d70c7ef94684bbfc0155314bcd2e3961fa';

/// The agent profile the last saved automation used in this session, so the
/// next one starts with it.

abstract class _$AutomationLastAgentProfile extends $Notifier<String?> {
  String? build();
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
    return element.handleCreate(ref, build);
  }
}
