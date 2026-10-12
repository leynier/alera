// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runRepository)
final runRepositoryProvider = RunRepositoryProvider._();

final class RunRepositoryProvider
    extends $FunctionalProvider<RunRepository, RunRepository, RunRepository>
    with $Provider<RunRepository> {
  RunRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runRepositoryHash();

  @$internal
  @override
  $ProviderElement<RunRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RunRepository create(Ref ref) {
    return runRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RunRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RunRepository>(value),
    );
  }
}

String _$runRepositoryHash() => r'599c2023a018d495a09eb7736d43d3f60f27e8e5';

@ProviderFor(recipeRepository)
final recipeRepositoryProvider = RecipeRepositoryProvider._();

final class RecipeRepositoryProvider
    extends
        $FunctionalProvider<
          RecipeRepository,
          RecipeRepository,
          RecipeRepository
        >
    with $Provider<RecipeRepository> {
  RecipeRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recipeRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recipeRepositoryHash();

  @$internal
  @override
  $ProviderElement<RecipeRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RecipeRepository create(Ref ref) {
    return recipeRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecipeRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecipeRepository>(value),
    );
  }
}

String _$recipeRepositoryHash() => r'bdec3e82911ada545678ba8161e8f4ca8e736d99';

/// The clock run rows and timelines measure ages against; tests pin it.

@ProviderFor(runClock)
final runClockProvider = RunClockProvider._();

/// The clock run rows and timelines measure ages against; tests pin it.

final class RunClockProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// The clock run rows and timelines measure ages against; tests pin it.
  RunClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runClockProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runClockHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return runClock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$runClockHash() => r'919e161d9fddcd9503a4bd5c75cc8cba33635b79';
