// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aleraDatabase)
final aleraDatabaseProvider = AleraDatabaseProvider._();

final class AleraDatabaseProvider
    extends
        $FunctionalProvider<
          AsyncValue<AleraDatabase>,
          AleraDatabase,
          FutureOr<AleraDatabase>
        >
    with $FutureModifier<AleraDatabase>, $FutureProvider<AleraDatabase> {
  AleraDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aleraDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aleraDatabaseHash();

  @$internal
  @override
  $FutureProviderElement<AleraDatabase> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AleraDatabase> create(Ref ref) {
    return aleraDatabase(ref);
  }
}

String _$aleraDatabaseHash() => r'8c54f0ff8e078dc6fbe699f1089f17a3d393cbbc';
