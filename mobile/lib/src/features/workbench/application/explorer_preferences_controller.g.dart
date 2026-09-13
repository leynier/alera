// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'explorer_preferences_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(explorerPreferencesRepository)
final explorerPreferencesRepositoryProvider =
    ExplorerPreferencesRepositoryProvider._();

final class ExplorerPreferencesRepositoryProvider
    extends
        $FunctionalProvider<
          ExplorerPreferencesRepository,
          ExplorerPreferencesRepository,
          ExplorerPreferencesRepository
        >
    with $Provider<ExplorerPreferencesRepository> {
  ExplorerPreferencesRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'explorerPreferencesRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$explorerPreferencesRepositoryHash();

  @$internal
  @override
  $ProviderElement<ExplorerPreferencesRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ExplorerPreferencesRepository create(Ref ref) {
    return explorerPreferencesRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExplorerPreferencesRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExplorerPreferencesRepository>(
        value,
      ),
    );
  }
}

String _$explorerPreferencesRepositoryHash() =>
    r'354fe83d0437a700fe475351bd1bfb8cd431413d';

/// Shared by the Explorer and Source Control panels so a root chosen in one is
/// what the other reads.

@ProviderFor(ExplorerPreferencesController)
final explorerPreferencesControllerProvider =
    ExplorerPreferencesControllerFamily._();

/// Shared by the Explorer and Source Control panels so a root chosen in one is
/// what the other reads.
final class ExplorerPreferencesControllerProvider
    extends
        $AsyncNotifierProvider<
          ExplorerPreferencesController,
          ExplorerPreferences
        > {
  /// Shared by the Explorer and Source Control panels so a root chosen in one is
  /// what the other reads.
  ExplorerPreferencesControllerProvider._({
    required ExplorerPreferencesControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'explorerPreferencesControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$explorerPreferencesControllerHash();

  @override
  String toString() {
    return r'explorerPreferencesControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ExplorerPreferencesController create() => ExplorerPreferencesController();

  @override
  bool operator ==(Object other) {
    return other is ExplorerPreferencesControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$explorerPreferencesControllerHash() =>
    r'1fba49513990a97c3a304a24c2f6fa997e8da3aa';

/// Shared by the Explorer and Source Control panels so a root chosen in one is
/// what the other reads.

final class ExplorerPreferencesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ExplorerPreferencesController,
          AsyncValue<ExplorerPreferences>,
          ExplorerPreferences,
          FutureOr<ExplorerPreferences>,
          (String, String)
        > {
  ExplorerPreferencesControllerFamily._()
    : super(
        retry: null,
        name: r'explorerPreferencesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Shared by the Explorer and Source Control panels so a root chosen in one is
  /// what the other reads.

  ExplorerPreferencesControllerProvider call(
    String hostId,
    String workspaceId,
  ) => ExplorerPreferencesControllerProvider._(
    argument: (hostId, workspaceId),
    from: this,
  );

  @override
  String toString() => r'explorerPreferencesControllerProvider';
}

/// Shared by the Explorer and Source Control panels so a root chosen in one is
/// what the other reads.

abstract class _$ExplorerPreferencesController
    extends $AsyncNotifier<ExplorerPreferences> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get workspaceId => _$args.$2;

  FutureOr<ExplorerPreferences> build(String hostId, String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ExplorerPreferences>, ExplorerPreferences>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ExplorerPreferences>, ExplorerPreferences>,
              AsyncValue<ExplorerPreferences>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
