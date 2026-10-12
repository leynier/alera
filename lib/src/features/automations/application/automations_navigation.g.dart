// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automations_navigation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AutomationsNavigation)
final automationsNavigationProvider = AutomationsNavigationProvider._();

final class AutomationsNavigationProvider
    extends $NotifierProvider<AutomationsNavigation, AutomationsLocation> {
  AutomationsNavigationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationsNavigationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationsNavigationHash();

  @$internal
  @override
  AutomationsNavigation create() => AutomationsNavigation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AutomationsLocation value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AutomationsLocation>(value),
    );
  }
}

String _$automationsNavigationHash() =>
    r'73d3a440093e6f7e6bafb22d60745b91cdc93755';

abstract class _$AutomationsNavigation extends $Notifier<AutomationsLocation> {
  AutomationsLocation build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AutomationsLocation, AutomationsLocation>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AutomationsLocation, AutomationsLocation>,
              AutomationsLocation,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
