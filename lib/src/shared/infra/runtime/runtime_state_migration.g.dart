// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_state_migration.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runtimeStateMigration)
final runtimeStateMigrationProvider = RuntimeStateMigrationProvider._();

final class RuntimeStateMigrationProvider
    extends
        $FunctionalProvider<
          RuntimeStateMigration,
          RuntimeStateMigration,
          RuntimeStateMigration
        >
    with $Provider<RuntimeStateMigration> {
  RuntimeStateMigrationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeStateMigrationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeStateMigrationHash();

  @$internal
  @override
  $ProviderElement<RuntimeStateMigration> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeStateMigration create(Ref ref) {
    return runtimeStateMigration(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeStateMigration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeStateMigration>(value),
    );
  }
}

String _$runtimeStateMigrationHash() =>
    r'bd8176527769e5f343d1b3f0f236d50f4d90ced2';
