// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reading_diff_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(readingDiffService)
final readingDiffServiceProvider = ReadingDiffServiceProvider._();

final class ReadingDiffServiceProvider
    extends
        $FunctionalProvider<
          ReadingDiffService,
          ReadingDiffService,
          ReadingDiffService
        >
    with $Provider<ReadingDiffService> {
  ReadingDiffServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'readingDiffServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$readingDiffServiceHash();

  @$internal
  @override
  $ProviderElement<ReadingDiffService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReadingDiffService create(Ref ref) {
    return readingDiffService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReadingDiffService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReadingDiffService>(value),
    );
  }
}

String _$readingDiffServiceHash() =>
    r'bf42911c35f86d6d9a2bd68f749c0fa6ed565bff';
