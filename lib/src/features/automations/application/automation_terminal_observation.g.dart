// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_terminal_observation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tabs this client took over, so a re-attach uses the normal mode at once
/// instead of waiting for the tab record to carry the takeover mark.

@ProviderFor(AutomationTakenOverTabs)
final automationTakenOverTabsProvider = AutomationTakenOverTabsProvider._();

/// Tabs this client took over, so a re-attach uses the normal mode at once
/// instead of waiting for the tab record to carry the takeover mark.
final class AutomationTakenOverTabsProvider
    extends $NotifierProvider<AutomationTakenOverTabs, Set<String>> {
  /// Tabs this client took over, so a re-attach uses the normal mode at once
  /// instead of waiting for the tab record to carry the takeover mark.
  AutomationTakenOverTabsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationTakenOverTabsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationTakenOverTabsHash();

  @$internal
  @override
  AutomationTakenOverTabs create() => AutomationTakenOverTabs();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$automationTakenOverTabsHash() =>
    r'001ecc68630d2a5624b9ba945c403ec54b2d9061';

/// Tabs this client took over, so a re-attach uses the normal mode at once
/// instead of waiting for the tab record to carry the takeover mark.

abstract class _$AutomationTakenOverTabs extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
