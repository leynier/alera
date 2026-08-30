// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_ai_dictation_model_transfers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MobileAiDictationModelTransfers)
final mobileAiDictationModelTransfersProvider =
    MobileAiDictationModelTransfersProvider._();

final class MobileAiDictationModelTransfersProvider
    extends
        $NotifierProvider<
          MobileAiDictationModelTransfers,
          MobileAiModelTransfersState
        > {
  MobileAiDictationModelTransfersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileAiDictationModelTransfersProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileAiDictationModelTransfersHash();

  @$internal
  @override
  MobileAiDictationModelTransfers create() => MobileAiDictationModelTransfers();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileAiModelTransfersState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileAiModelTransfersState>(value),
    );
  }
}

String _$mobileAiDictationModelTransfersHash() =>
    r'179eb8b4e3f18a41a9fc587611107fd9fb9b358b';

abstract class _$MobileAiDictationModelTransfers
    extends $Notifier<MobileAiModelTransfersState> {
  MobileAiModelTransfersState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<MobileAiModelTransfersState, MobileAiModelTransfersState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                MobileAiModelTransfersState,
                MobileAiModelTransfersState
              >,
              MobileAiModelTransfersState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
