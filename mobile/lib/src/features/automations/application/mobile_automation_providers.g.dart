// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_automation_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mobileAutomations)
final mobileAutomationsProvider = MobileAutomationsFamily._();

final class MobileAutomationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MobileAutomation>>,
          List<MobileAutomation>,
          FutureOr<List<MobileAutomation>>
        >
    with
        $FutureModifier<List<MobileAutomation>>,
        $FutureProvider<List<MobileAutomation>> {
  MobileAutomationsProvider._({
    required MobileAutomationsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationsHash();

  @override
  String toString() {
    return r'mobileAutomationsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<MobileAutomation>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<MobileAutomation>> create(Ref ref) {
    final argument = this.argument as String;
    return mobileAutomations(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationsHash() => r'4da715888dcde64ee813aebe6ae77346034ef55f';

final class MobileAutomationsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<MobileAutomation>>, String> {
  MobileAutomationsFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAutomationsProvider call(String hostId) =>
      MobileAutomationsProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationsProvider';
}

@ProviderFor(mobileAutomationCatalog)
final mobileAutomationCatalogProvider = MobileAutomationCatalogFamily._();

final class MobileAutomationCatalogProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MobileAutomation>>,
          List<MobileAutomation>,
          FutureOr<List<MobileAutomation>>
        >
    with
        $FutureModifier<List<MobileAutomation>>,
        $FutureProvider<List<MobileAutomation>> {
  MobileAutomationCatalogProvider._({
    required MobileAutomationCatalogFamily super.from,
    required (String, bool) super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationCatalogProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationCatalogHash();

  @override
  String toString() {
    return r'mobileAutomationCatalogProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<MobileAutomation>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<MobileAutomation>> create(Ref ref) {
    final argument = this.argument as (String, bool);
    return mobileAutomationCatalog(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationCatalogProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationCatalogHash() =>
    r'8217fb71a0d98e77d4234025f80d7a53105cfa80';

final class MobileAutomationCatalogFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<MobileAutomation>>,
          (String, bool)
        > {
  MobileAutomationCatalogFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationCatalogProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAutomationCatalogProvider call(String hostId, bool includeTrashed) =>
      MobileAutomationCatalogProvider._(
        argument: (hostId, includeTrashed),
        from: this,
      );

  @override
  String toString() => r'mobileAutomationCatalogProvider';
}
