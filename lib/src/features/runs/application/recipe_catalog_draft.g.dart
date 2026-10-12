// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recipe_catalog_draft.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(RecipeCatalogDraft)
final recipeCatalogDraftProvider = RecipeCatalogDraftProvider._();

final class RecipeCatalogDraftProvider
    extends $NotifierProvider<RecipeCatalogDraft, RecipeCatalogEdit?> {
  RecipeCatalogDraftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recipeCatalogDraftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recipeCatalogDraftHash();

  @$internal
  @override
  RecipeCatalogDraft create() => RecipeCatalogDraft();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecipeCatalogEdit? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecipeCatalogEdit?>(value),
    );
  }
}

String _$recipeCatalogDraftHash() =>
    r'aef354be5b5bd0c1e67f0ae7d1349b5803c3bf37';

abstract class _$RecipeCatalogDraft extends $Notifier<RecipeCatalogEdit?> {
  RecipeCatalogEdit? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RecipeCatalogEdit?, RecipeCatalogEdit?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RecipeCatalogEdit?, RecipeCatalogEdit?>,
              RecipeCatalogEdit?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
