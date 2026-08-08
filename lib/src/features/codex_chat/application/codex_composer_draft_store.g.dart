// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'codex_composer_draft_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(codexComposerDraftStore)
final codexComposerDraftStoreProvider = CodexComposerDraftStoreProvider._();

final class CodexComposerDraftStoreProvider
    extends
        $FunctionalProvider<
          CodexComposerDraftStore,
          CodexComposerDraftStore,
          CodexComposerDraftStore
        >
    with $Provider<CodexComposerDraftStore> {
  CodexComposerDraftStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'codexComposerDraftStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$codexComposerDraftStoreHash();

  @$internal
  @override
  $ProviderElement<CodexComposerDraftStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CodexComposerDraftStore create(Ref ref) {
    return codexComposerDraftStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CodexComposerDraftStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CodexComposerDraftStore>(value),
    );
  }
}

String _$codexComposerDraftStoreHash() =>
    r'b5f7758464980d1bc1645d62240e6d39cd3c4272';
