// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_dictation_model_transfers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AiDictationModelTransfers)
final aiDictationModelTransfersProvider = AiDictationModelTransfersProvider._();

final class AiDictationModelTransfersProvider
    extends
        $NotifierProvider<
          AiDictationModelTransfers,
          AiDictationModelTransfersState
        > {
  AiDictationModelTransfersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiDictationModelTransfersProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiDictationModelTransfersHash();

  @$internal
  @override
  AiDictationModelTransfers create() => AiDictationModelTransfers();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiDictationModelTransfersState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiDictationModelTransfersState>(
        value,
      ),
    );
  }
}

String _$aiDictationModelTransfersHash() =>
    r'e8e1d3f273d74c9b6c1840cc3d0ea7e850b4bc30';

abstract class _$AiDictationModelTransfers
    extends $Notifier<AiDictationModelTransfersState> {
  AiDictationModelTransfersState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AiDictationModelTransfersState,
              AiDictationModelTransfersState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AiDictationModelTransfersState,
                AiDictationModelTransfersState
              >,
              AiDictationModelTransfersState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
