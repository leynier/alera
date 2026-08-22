// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_codex_composer_draft_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mobileCodexComposerDraftStore)
final mobileCodexComposerDraftStoreProvider =
    MobileCodexComposerDraftStoreProvider._();

final class MobileCodexComposerDraftStoreProvider
    extends
        $FunctionalProvider<
          MobileCodexComposerDraftStore,
          MobileCodexComposerDraftStore,
          MobileCodexComposerDraftStore
        >
    with $Provider<MobileCodexComposerDraftStore> {
  MobileCodexComposerDraftStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileCodexComposerDraftStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileCodexComposerDraftStoreHash();

  @$internal
  @override
  $ProviderElement<MobileCodexComposerDraftStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MobileCodexComposerDraftStore create(Ref ref) {
    return mobileCodexComposerDraftStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileCodexComposerDraftStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileCodexComposerDraftStore>(
        value,
      ),
    );
  }
}

String _$mobileCodexComposerDraftStoreHash() =>
    r'85449e52cb2d5712a77aa8bdce4519b62c38aeb0';
