// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'background_operations.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns submissions after their form closes. Failed writes are never replayed
/// automatically: the server may already have applied part of the operation.

@ProviderFor(BackgroundOperations)
final backgroundOperationsProvider = BackgroundOperationsProvider._();

/// Owns submissions after their form closes. Failed writes are never replayed
/// automatically: the server may already have applied part of the operation.
final class BackgroundOperationsProvider
    extends $NotifierProvider<BackgroundOperations, List<BackgroundOperation>> {
  /// Owns submissions after their form closes. Failed writes are never replayed
  /// automatically: the server may already have applied part of the operation.
  BackgroundOperationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backgroundOperationsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backgroundOperationsHash();

  @$internal
  @override
  BackgroundOperations create() => BackgroundOperations();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<BackgroundOperation> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<BackgroundOperation>>(value),
    );
  }
}

String _$backgroundOperationsHash() =>
    r'078b22d7793686f36254b36d46f437ff9f23d473';

/// Owns submissions after their form closes. Failed writes are never replayed
/// automatically: the server may already have applied part of the operation.

abstract class _$BackgroundOperations
    extends $Notifier<List<BackgroundOperation>> {
  List<BackgroundOperation> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<List<BackgroundOperation>, List<BackgroundOperation>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<BackgroundOperation>, List<BackgroundOperation>>,
              List<BackgroundOperation>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
