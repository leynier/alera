// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_codex_preferences_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mobileCodexPreferencesRepository)
final mobileCodexPreferencesRepositoryProvider =
    MobileCodexPreferencesRepositoryProvider._();

final class MobileCodexPreferencesRepositoryProvider
    extends
        $FunctionalProvider<
          MobileCodexPreferencesRepository,
          MobileCodexPreferencesRepository,
          MobileCodexPreferencesRepository
        >
    with $Provider<MobileCodexPreferencesRepository> {
  MobileCodexPreferencesRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileCodexPreferencesRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileCodexPreferencesRepositoryHash();

  @$internal
  @override
  $ProviderElement<MobileCodexPreferencesRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MobileCodexPreferencesRepository create(Ref ref) {
    return mobileCodexPreferencesRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileCodexPreferencesRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileCodexPreferencesRepository>(
        value,
      ),
    );
  }
}

String _$mobileCodexPreferencesRepositoryHash() =>
    r'8f785f01cf92141d155cbb58e12eae358a1b348e';
