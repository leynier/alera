// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_automation_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The paired runtime as the Automations screens see it. Rebuilds with every
/// reconnection, which reloads everything that depends on it.

@ProviderFor(mobileAutomationClient)
final mobileAutomationClientProvider = MobileAutomationClientFamily._();

/// The paired runtime as the Automations screens see it. Rebuilds with every
/// reconnection, which reloads everything that depends on it.

final class MobileAutomationClientProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileAutomationClient>,
          MobileAutomationClient,
          FutureOr<MobileAutomationClient>
        >
    with
        $FutureModifier<MobileAutomationClient>,
        $FutureProvider<MobileAutomationClient> {
  /// The paired runtime as the Automations screens see it. Rebuilds with every
  /// reconnection, which reloads everything that depends on it.
  MobileAutomationClientProvider._({
    required MobileAutomationClientFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationClientProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationClientHash();

  @override
  String toString() {
    return r'mobileAutomationClientProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileAutomationClient> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileAutomationClient> create(Ref ref) {
    final argument = this.argument as String;
    return mobileAutomationClient(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationClientProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationClientHash() =>
    r'4711ca50a5064d1429ab261c5823f026fbdb391b';

/// The paired runtime as the Automations screens see it. Rebuilds with every
/// reconnection, which reloads everything that depends on it.

final class MobileAutomationClientFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<MobileAutomationClient>, String> {
  MobileAutomationClientFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationClientProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The paired runtime as the Automations screens see it. Rebuilds with every
  /// reconnection, which reloads everything that depends on it.

  MobileAutomationClientProvider call(String hostId) =>
      MobileAutomationClientProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationClientProvider';
}

@ProviderFor(mobileAutomationRepository)
final mobileAutomationRepositoryProvider = MobileAutomationRepositoryFamily._();

final class MobileAutomationRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileRuntimeAutomationRepository>,
          MobileRuntimeAutomationRepository,
          FutureOr<MobileRuntimeAutomationRepository>
        >
    with
        $FutureModifier<MobileRuntimeAutomationRepository>,
        $FutureProvider<MobileRuntimeAutomationRepository> {
  MobileAutomationRepositoryProvider._({
    required MobileAutomationRepositoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationRepositoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationRepositoryHash();

  @override
  String toString() {
    return r'mobileAutomationRepositoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileRuntimeAutomationRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileRuntimeAutomationRepository> create(Ref ref) {
    final argument = this.argument as String;
    return mobileAutomationRepository(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationRepositoryProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationRepositoryHash() =>
    r'a88040fdbdf37ea386dc11738d79ddb1791ec639';

final class MobileAutomationRepositoryFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<MobileRuntimeAutomationRepository>,
          String
        > {
  MobileAutomationRepositoryFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationRepositoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAutomationRepositoryProvider call(String hostId) =>
      MobileAutomationRepositoryProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationRepositoryProvider';
}

/// The whole catalog of the host, trash included. Lifecycle events reload it;
/// the previous list stays visible while that happens.

@ProviderFor(MobileAutomationCatalog)
final mobileAutomationCatalogProvider = MobileAutomationCatalogFamily._();

/// The whole catalog of the host, trash included. Lifecycle events reload it;
/// the previous list stays visible while that happens.
final class MobileAutomationCatalogProvider
    extends
        $AsyncNotifierProvider<
          MobileAutomationCatalog,
          List<AutomationRecord>
        > {
  /// The whole catalog of the host, trash included. Lifecycle events reload it;
  /// the previous list stays visible while that happens.
  MobileAutomationCatalogProvider._({
    required MobileAutomationCatalogFamily super.from,
    required String super.argument,
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
        '($argument)';
  }

  @$internal
  @override
  MobileAutomationCatalog create() => MobileAutomationCatalog();

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
    r'ecc0ad6c14e9aed6ac1da6b977d6d905dd54c077';

/// The whole catalog of the host, trash included. Lifecycle events reload it;
/// the previous list stays visible while that happens.

final class MobileAutomationCatalogFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAutomationCatalog,
          AsyncValue<List<AutomationRecord>>,
          List<AutomationRecord>,
          FutureOr<List<AutomationRecord>>,
          String
        > {
  MobileAutomationCatalogFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationCatalogProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The whole catalog of the host, trash included. Lifecycle events reload it;
  /// the previous list stays visible while that happens.

  MobileAutomationCatalogProvider call(String hostId) =>
      MobileAutomationCatalogProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationCatalogProvider';
}

/// The whole catalog of the host, trash included. Lifecycle events reload it;
/// the previous list stays visible while that happens.

abstract class _$MobileAutomationCatalog
    extends $AsyncNotifier<List<AutomationRecord>> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<List<AutomationRecord>> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<AutomationRecord>>, List<AutomationRecord>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<AutomationRecord>>,
                List<AutomationRecord>
              >,
              AsyncValue<List<AutomationRecord>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(MobileAutomationDetail)
final mobileAutomationDetailProvider = MobileAutomationDetailFamily._();

final class MobileAutomationDetailProvider
    extends $AsyncNotifierProvider<MobileAutomationDetail, AutomationDetail> {
  MobileAutomationDetailProvider._({
    required MobileAutomationDetailFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationDetailHash();

  @override
  String toString() {
    return r'mobileAutomationDetailProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileAutomationDetail create() => MobileAutomationDetail();

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationDetailProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationDetailHash() =>
    r'544494d09216596ce3a867bc5fc2303a0f68573e';

final class MobileAutomationDetailFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAutomationDetail,
          AsyncValue<AutomationDetail>,
          AutomationDetail,
          FutureOr<AutomationDetail>,
          (String, String)
        > {
  MobileAutomationDetailFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAutomationDetailProvider call(String hostId, String id) =>
      MobileAutomationDetailProvider._(argument: (hostId, id), from: this);

  @override
  String toString() => r'mobileAutomationDetailProvider';
}

abstract class _$MobileAutomationDetail
    extends $AsyncNotifier<AutomationDetail> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get id => _$args.$2;

  FutureOr<AutomationDetail> build(String hostId, String id);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<AutomationDetail>, AutomationDetail>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AutomationDetail>, AutomationDetail>,
              AsyncValue<AutomationDetail>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

@ProviderFor(MobileAutomationRecentRuns)
final mobileAutomationRecentRunsProvider = MobileAutomationRecentRunsFamily._();

final class MobileAutomationRecentRunsProvider
    extends
        $AsyncNotifierProvider<
          MobileAutomationRecentRuns,
          List<AutomationRunRecord>
        > {
  MobileAutomationRecentRunsProvider._({
    required MobileAutomationRecentRunsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationRecentRunsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationRecentRunsHash();

  @override
  String toString() {
    return r'mobileAutomationRecentRunsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileAutomationRecentRuns create() => MobileAutomationRecentRuns();

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationRecentRunsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationRecentRunsHash() =>
    r'daae83b04f30d43d7c6b2d7f0b68d7b21ec2bdf6';

final class MobileAutomationRecentRunsFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAutomationRecentRuns,
          AsyncValue<List<AutomationRunRecord>>,
          List<AutomationRunRecord>,
          FutureOr<List<AutomationRunRecord>>,
          String
        > {
  MobileAutomationRecentRunsFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationRecentRunsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAutomationRecentRunsProvider call(String hostId) =>
      MobileAutomationRecentRunsProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationRecentRunsProvider';
}

abstract class _$MobileAutomationRecentRuns
    extends $AsyncNotifier<List<AutomationRunRecord>> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<List<AutomationRunRecord>> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<AutomationRunRecord>>,
              List<AutomationRunRecord>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<AutomationRunRecord>>,
                List<AutomationRunRecord>
              >,
              AsyncValue<List<AutomationRunRecord>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Scope and filters of the list, kept per host while the app runs.

@ProviderFor(MobileAutomationListController)
final mobileAutomationListControllerProvider =
    MobileAutomationListControllerFamily._();

/// Scope and filters of the list, kept per host while the app runs.
final class MobileAutomationListControllerProvider
    extends
        $NotifierProvider<
          MobileAutomationListController,
          MobileAutomationListState
        > {
  /// Scope and filters of the list, kept per host while the app runs.
  MobileAutomationListControllerProvider._({
    required MobileAutomationListControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationListControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationListControllerHash();

  @override
  String toString() {
    return r'mobileAutomationListControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileAutomationListController create() => MobileAutomationListController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileAutomationListState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileAutomationListState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationListControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationListControllerHash() =>
    r'279bf5e57e4504a7eb8010cdabe7621f4b8856c4';

/// Scope and filters of the list, kept per host while the app runs.

final class MobileAutomationListControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAutomationListController,
          MobileAutomationListState,
          MobileAutomationListState,
          MobileAutomationListState,
          String
        > {
  MobileAutomationListControllerFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationListControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Scope and filters of the list, kept per host while the app runs.

  MobileAutomationListControllerProvider call(String hostId) =>
      MobileAutomationListControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationListControllerProvider';
}

/// Scope and filters of the list, kept per host while the app runs.

abstract class _$MobileAutomationListController
    extends $Notifier<MobileAutomationListState> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  MobileAutomationListState build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<MobileAutomationListState, MobileAutomationListState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MobileAutomationListState, MobileAutomationListState>,
              MobileAutomationListState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Tabs this phone took over, so the terminal re-attaches normally at once.

@ProviderFor(MobileAutomationTakenOverTabs)
final mobileAutomationTakenOverTabsProvider =
    MobileAutomationTakenOverTabsFamily._();

/// Tabs this phone took over, so the terminal re-attaches normally at once.
final class MobileAutomationTakenOverTabsProvider
    extends $NotifierProvider<MobileAutomationTakenOverTabs, Set<String>> {
  /// Tabs this phone took over, so the terminal re-attaches normally at once.
  MobileAutomationTakenOverTabsProvider._({
    required MobileAutomationTakenOverTabsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationTakenOverTabsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationTakenOverTabsHash();

  @override
  String toString() {
    return r'mobileAutomationTakenOverTabsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileAutomationTakenOverTabs create() => MobileAutomationTakenOverTabs();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationTakenOverTabsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationTakenOverTabsHash() =>
    r'0ab87818e3a9b20a3979ccf0b47654571aa554a8';

/// Tabs this phone took over, so the terminal re-attaches normally at once.

final class MobileAutomationTakenOverTabsFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAutomationTakenOverTabs,
          Set<String>,
          Set<String>,
          Set<String>,
          String
        > {
  MobileAutomationTakenOverTabsFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationTakenOverTabsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Tabs this phone took over, so the terminal re-attaches normally at once.

  MobileAutomationTakenOverTabsProvider call(String hostId) =>
      MobileAutomationTakenOverTabsProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationTakenOverTabsProvider';
}

/// Tabs this phone took over, so the terminal re-attaches normally at once.

abstract class _$MobileAutomationTakenOverTabs extends $Notifier<Set<String>> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  Set<String> build(String hostId);
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
    return element.handleCreate(ref, () => build(_$args));
  }
}
