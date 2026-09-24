// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voice_session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runtimeVoiceClient)
final runtimeVoiceClientProvider = RuntimeVoiceClientProvider._();

final class RuntimeVoiceClientProvider
    extends
        $FunctionalProvider<
          RuntimeVoiceClient,
          RuntimeVoiceClient,
          RuntimeVoiceClient
        >
    with $Provider<RuntimeVoiceClient> {
  RuntimeVoiceClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeVoiceClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeVoiceClientHash();

  @$internal
  @override
  $ProviderElement<RuntimeVoiceClient> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeVoiceClient create(Ref ref) {
    return runtimeVoiceClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeVoiceClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeVoiceClient>(value),
    );
  }
}

String _$runtimeVoiceClientHash() =>
    r'969a2d25d7421023811967c18f3d6569e872c149';

@ProviderFor(voiceHomeAgentSupported)
final voiceHomeAgentSupportedProvider = VoiceHomeAgentSupportedProvider._();

final class VoiceHomeAgentSupportedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  VoiceHomeAgentSupportedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voiceHomeAgentSupportedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voiceHomeAgentSupportedHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return voiceHomeAgentSupported(ref);
  }
}

String _$voiceHomeAgentSupportedHash() =>
    r'3d4f66a7e465425121f138d4c4a06f8deaf36e13';

@ProviderFor(VoiceSessionController)
final voiceSessionControllerProvider = VoiceSessionControllerProvider._();

final class VoiceSessionControllerProvider
    extends $NotifierProvider<VoiceSessionController, VoiceSessionStatus> {
  VoiceSessionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voiceSessionControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voiceSessionControllerHash();

  @$internal
  @override
  VoiceSessionController create() => VoiceSessionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VoiceSessionStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VoiceSessionStatus>(value),
    );
  }
}

String _$voiceSessionControllerHash() =>
    r'8ed7d2b0b0d20dfd1e4204a3b7266810cd7dd8c6';

abstract class _$VoiceSessionController extends $Notifier<VoiceSessionStatus> {
  VoiceSessionStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VoiceSessionStatus, VoiceSessionStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VoiceSessionStatus, VoiceSessionStatus>,
              VoiceSessionStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
