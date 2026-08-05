// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automation_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(automationRepository)
final automationRepositoryProvider = AutomationRepositoryProvider._();

final class AutomationRepositoryProvider
    extends
        $FunctionalProvider<
          RuntimeAutomationRepository,
          RuntimeAutomationRepository,
          RuntimeAutomationRepository
        >
    with $Provider<RuntimeAutomationRepository> {
  AutomationRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationRepositoryHash();

  @$internal
  @override
  $ProviderElement<RuntimeAutomationRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeAutomationRepository create(Ref ref) {
    return automationRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeAutomationRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeAutomationRepository>(value),
    );
  }
}

String _$automationRepositoryHash() =>
    r'fc00105a888176b8459c27e7d6785b0192c618a1';

@ProviderFor(automationList)
final automationListProvider = AutomationListProvider._();

final class AutomationListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AutomationRecord>>,
          List<AutomationRecord>,
          Stream<List<AutomationRecord>>
        >
    with
        $FutureModifier<List<AutomationRecord>>,
        $StreamProvider<List<AutomationRecord>> {
  AutomationListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'automationListProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$automationListHash();

  @$internal
  @override
  $StreamProviderElement<List<AutomationRecord>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<AutomationRecord>> create(Ref ref) {
    return automationList(ref);
  }
}

String _$automationListHash() => r'4355c87f26029b93158c06754ded044e990d85d8';

@ProviderFor(automationCatalog)
final automationCatalogProvider = AutomationCatalogFamily._();

final class AutomationCatalogProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AutomationRecord>>,
          List<AutomationRecord>,
          Stream<List<AutomationRecord>>
        >
    with
        $FutureModifier<List<AutomationRecord>>,
        $StreamProvider<List<AutomationRecord>> {
  AutomationCatalogProvider._({
    required AutomationCatalogFamily super.from,
    required bool super.argument,
  }) : super(
         retry: null,
         name: r'automationCatalogProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$automationCatalogHash();

  @override
  String toString() {
    return r'automationCatalogProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<AutomationRecord>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<AutomationRecord>> create(Ref ref) {
    final argument = this.argument as bool;
    return automationCatalog(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AutomationCatalogProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$automationCatalogHash() => r'624ddda329b97326c9e67880f83701fce0620c49';

final class AutomationCatalogFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<AutomationRecord>>, bool> {
  AutomationCatalogFamily._()
    : super(
        retry: null,
        name: r'automationCatalogProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AutomationCatalogProvider call(bool includeTrashed) =>
      AutomationCatalogProvider._(argument: includeTrashed, from: this);

  @override
  String toString() => r'automationCatalogProvider';
}
